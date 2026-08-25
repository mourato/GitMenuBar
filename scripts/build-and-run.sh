#!/bin/bash
# build-and-run.sh - Build Debug or install the Release app transactionally.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_ROOT}/scripts/config/app_identity.sh"

CONFIGURATION=""
CLEAN=0
NO_INTERACTIVE=0
FORCE_TERMINATE=0
SKIP_LAUNCH=0
CONFIRM_INSTALL=1
SIGNING_IDENTITY="${GITMENUBAR_CODE_SIGN_IDENTITY:-}"
APPLICATIONS_DIR="${GITMENUBAR_APPLICATIONS_DIR:-/Applications}"
SHUTDOWN_TIMEOUT="${GITMENUBAR_SHUTDOWN_TIMEOUT_SECONDS:-15}"
STARTUP_TIMEOUT="${GITMENUBAR_STARTUP_TIMEOUT_SECONDS:-15}"

usage() {
    cat <<'USAGE'
Usage: scripts/build-and-run.sh [options]

Build Debug for local iteration or build/install Release into GitMenuBar.app.

Options:
  --configuration Debug|Release  Select a deterministic build mode.
  --clean                        Remove this repository's .xcode-build first.
  --no-interactive               Never read stdin; requires --configuration.
  --force-terminate              Allow exact-process TERM fallback after graceful timeout.
  --skip-launch                  Verify Release installation without relaunching it.
  --yes                          In interactive Release mode, accept the install default.
  --applications-dir PATH        Test-only applications root; defaults to /Applications.
  --sign-identity IDENTITY       Re-sign Release candidate before installation.
  --help                         Show this help without building.

Environment:
  GITMENUBAR_APPLICATIONS_DIR        Override installation root for tests.
  GITMENUBAR_CODE_SIGN_IDENTITY      Default signing identity for --sign-identity.
  GITMENUBAR_SHUTDOWN_TIMEOUT_SECONDS
  GITMENUBAR_STARTUP_TIMEOUT_SECONDS
USAGE
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

prompt() {
    local message="$1" default="$2" reply
    read -r -p "${message} [${default}]: " reply < /dev/tty || reply=""
    printf '%s\n' "${reply:-$default}"
}

confirm_default_yes() {
    local message="$1" reply
    read -r -p "${message} [Y/n]: " reply < /dev/tty || reply=""
    case "$reply" in
        ""|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

require_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "timeout must be a positive integer: $1"
}

validate_applications_dir() {
    local root="$1" resolved
    [ -d "$root" ] || fail "applications directory does not exist: $root"
    resolved="$(cd "$root" && pwd -P)"
    [ "$resolved" != "/" ] || fail "refusing the filesystem root as an installation target"
    [ "$resolved" != "${HOME:-}" ] || fail "refusing the home directory as an installation target"
    printf '%s\n' "$resolved"
}

bundle_path() {
    printf '%s/%s.app\n' "$1" "$APP_PRODUCT_NAME"
}

bundle_identifier() {
    plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

validate_bundle() {
    local bundle="$1" identifier
    [ -d "$bundle" ] || return 1
    [ "$(basename "$bundle")" = "${APP_PRODUCT_NAME}.app" ] || return 1
    [ -f "$bundle/Contents/Info.plist" ] || return 1
    identifier="$(bundle_identifier "$bundle")"
    [ "$identifier" = "$APP_BUNDLE_IDENTIFIER" ] || return 1
    [ -x "$bundle/Contents/MacOS/${APP_PRODUCT_NAME}" ] || return 1
    codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 || return 1
}

sign_candidate_if_needed() {
    local candidate="$1"
    if codesign --verify --deep --strict "$candidate" >/dev/null 2>&1; then
        return 0
    fi

    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "Signing Release candidate with: ${SIGNING_IDENTITY}"
        codesign --force --deep --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$candidate"
    else
        echo "Release candidate is not signed for local install; applying ad-hoc signature."
        codesign --force --deep --sign - "$candidate"
    fi
}

running_pids_for_bundle() {
    local bundle="$1" executable pid command_path
    executable="${bundle}/Contents/MacOS/${APP_PRODUCT_NAME}"

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        command_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        [ "$command_path" = "$executable" ] && printf '%s\n' "$pid"
    done < <(pgrep -x "$APP_PRODUCT_NAME" 2>/dev/null || true)
    return 0
}

wait_for_exit() {
    local bundle="$1"
    local deadline=$((SECONDS + SHUTDOWN_TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do
        [ -z "$(running_pids_for_bundle "$bundle")" ] && return 0
        sleep 1
    done
    return 1
}

stop_running_app() {
    local target="$1" pids
    pids="$(running_pids_for_bundle "$target")"
    [ -z "$pids" ] && return 0

    echo "Requesting graceful shutdown for running ${target}..."
    osascript -e "tell application id \"${APP_BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
    wait_for_exit "$target" && return 0

    if [ "$FORCE_TERMINATE" -ne 1 ] && [ "$NO_INTERACTIVE" -eq 0 ]; then
        if confirm_default_yes "Graceful shutdown timed out. Stop exact ${target} process now?"; then
            FORCE_TERMINATE=1
        fi
    fi

    if [ "$FORCE_TERMINATE" -ne 1 ]; then
        fail "${APP_PRODUCT_NAME} did not terminate within ${SHUTDOWN_TIMEOUT}s; rerun with --force-terminate only if intended"
    fi
    echo "Graceful shutdown timed out; sending TERM to PID(s): ${pids}" >&2
    while IFS= read -r pid; do
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
    done <<< "$pids"
    wait_for_exit "$target" || fail "${APP_PRODUCT_NAME} remained running after explicit TERM fallback"
}

rollback() {
    local target="$1" backup="$2"
    rm -rf "$target"
    if [ -d "$backup" ]; then
        mv "$backup" "$target"
        echo "Rollback restored ${target}" >&2
    else
        echo "Rollback had no previous bundle to restore" >&2
    fi
}

install_release() {
    local candidate target stage backup had_backup=0
    candidate="${PROJECT_ROOT}/.xcode-build/Build/Products/Release/${APP_PRODUCT_NAME}.app"
    target="$(bundle_path "$APPLICATIONS_DIR")"
    stage="${target}.stage.$$"
    backup="${target}.backup.$$"

    [ -d "$candidate" ] || fail "Release candidate not found at: $candidate"
    sign_candidate_if_needed "$candidate"
    validate_bundle "$candidate" || fail "Release candidate is not installable: $candidate"
    case "$target" in
        "${APPLICATIONS_DIR}/${APP_PRODUCT_NAME}.app") ;;
        *) fail "refusing unexpected installation target: $target" ;;
    esac

    if [ "$CONFIRM_INSTALL" -eq 1 ] && [ "$NO_INTERACTIVE" -eq 0 ]; then
        confirm_default_yes "Replace ${target} with the new Release build?" || exit 0
    fi

    stop_running_app "$target"
    rm -rf "$stage"
    ditto "$candidate" "$stage" || { rm -rf "$stage"; fail "could not stage Release candidate"; }

    if [ -e "$target" ]; then
        mv "$target" "$backup" || { rm -rf "$stage"; fail "could not create installation backup"; }
        had_backup=1
    fi

    if ! mv "$stage" "$target" || ! validate_bundle "$target"; then
        rm -rf "$stage"
        [ "$had_backup" -eq 1 ] && mv "$backup" "$target"
        fail "Release installation failed; rollback was attempted"
    fi

    if [ "$SKIP_LAUNCH" -eq 0 ]; then
        open "$target" >/dev/null 2>&1 || { rollback "$target" "$backup"; fail "Release app failed to launch"; }
        local deadline=$((SECONDS + STARTUP_TIMEOUT))
        while [ "$SECONDS" -lt "$deadline" ] && [ -z "$(running_pids_for_bundle "$target")" ]; do
            sleep 1
        done
        if [ -z "$(running_pids_for_bundle "$target")" ]; then
            rollback "$target" "$backup"
            fail "Release app did not remain alive after launch"
        fi
    fi

    rm -rf "$backup"
    echo "Installed and validated ${target}"
}

run_selected() {
    [ "$CLEAN" -eq 1 ] && rm -rf "$PROJECT_ROOT/.xcode-build"
    if [ "$CONFIGURATION" = "Debug" ]; then
        "$PROJECT_ROOT/scripts/run-build.sh" --configuration Debug
        open "$PROJECT_ROOT/.xcode-build/Build/Products/Debug/${APP_PRODUCT_NAME}.app"
    else
        APPLICATIONS_DIR="$(validate_applications_dir "$APPLICATIONS_DIR")"
        "$PROJECT_ROOT/scripts/run-build.sh" --configuration Release
        install_release
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            [ $# -ge 2 ] || fail "--configuration requires Debug or Release"
            CONFIGURATION="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --no-interactive)
            NO_INTERACTIVE=1
            CONFIRM_INSTALL=0
            shift
            ;;
        --force-terminate)
            FORCE_TERMINATE=1
            shift
            ;;
        --skip-launch)
            SKIP_LAUNCH=1
            shift
            ;;
        --yes)
            CONFIRM_INSTALL=0
            shift
            ;;
        --applications-dir)
            [ $# -ge 2 ] || fail "--applications-dir requires a path"
            APPLICATIONS_DIR="$2"
            shift 2
            ;;
        --sign-identity)
            [ $# -ge 2 ] || fail "--sign-identity requires an identity name"
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

require_positive_integer "$SHUTDOWN_TIMEOUT"
require_positive_integer "$STARTUP_TIMEOUT"

if [ "$NO_INTERACTIVE" -eq 1 ]; then
    [ -n "$CONFIGURATION" ] || fail "--no-interactive requires --configuration Debug|Release"
elif [ -z "$CONFIGURATION" ]; then
    [ -t 0 ] && [ -t 1 ] || fail "interactive selection requires a TTY; pass --no-interactive --configuration ..."
    echo "1) Release - build and replace $(bundle_path "$APPLICATIONS_DIR") [default]"
    echo "2) Debug - build and open local debug app"
    echo "3) Exit"
    choice="$(prompt "Choose" "1")"
    case "$choice" in
        1) CONFIGURATION=Release ;;
        2) CONFIGURATION=Debug ;;
        3) exit 0 ;;
        *) fail "invalid choice: $choice" ;;
    esac
    clean_choice="$(prompt "Clean .xcode-build first? Y/n" "Y")"
    case "$clean_choice" in
        y|Y|yes|YES) CLEAN=1 ;;
    esac
fi

case "$CONFIGURATION" in
    Debug|Release) ;;
    *) fail "configuration must be Debug or Release" ;;
esac

run_selected
