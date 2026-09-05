#!/usr/bin/env bash
set -euo pipefail

# test-hygiene: this is an explicit live AppKit/WindowServer exception. It is
# opt-in, uses an isolated bundle/defaults domain and temporary HOME, and the
# trap removes the launched process and seeded state.

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_NAME='GitMenuBar'
BUNDLE_ID="com.mourato.GitMenuBar.runtime-smoke.$$"
STARTUP_TIMEOUT="${GITMENUBAR_RUNTIME_SMOKE_TIMEOUT:-20}"
STABILITY_SECONDS="${GITMENUBAR_RUNTIME_SMOKE_STABILITY_SECONDS:-3}"

if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
    cat <<'EOF'
Usage: scripts/runtime-smoke.sh

Builds Debug, seeds a persisted main-window frame and inspector width in an
isolated defaults domain, launches the app, and checks process stability.
EOF
    exit 0
fi

[[ $# -eq 0 ]] || { printf 'error: unknown argument: %s\n' "$1" >&2; exit 2; }
[[ "$STARTUP_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { printf 'error: invalid startup timeout\n' >&2; exit 2; }
[[ "$STABILITY_SECONDS" =~ ^[1-9][0-9]*$ ]] || { printf 'error: invalid stability duration\n' >&2; exit 2; }

BUILD_ROOT="$PROJECT_ROOT/.xcode-build"
mkdir -p "$BUILD_ROOT"
DERIVED_DATA="$(mktemp -d "$BUILD_ROOT/runtime-smoke.XXXXXX")"
LOG_PATH="$DERIVED_DATA/runtime.log"
HOME_ROOT="$DERIVED_DATA/home"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
PID=''

cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.2
        done
        if kill -0 "$PID" 2>/dev/null; then
            kill -KILL "$PID" 2>/dev/null || true
        fi
        wait "$PID" 2>/dev/null || true
    fi
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'RUNTIME_SMOKE: FAIL reason=%s\n' "$1" >&2
    if [[ -s "$LOG_PATH" ]]; then
        tail -n 30 "$LOG_PATH" >&2 || true
    fi
    exit 1
}

mkdir -p "$HOME_ROOT"
defaults write "$BUNDLE_ID" 'NSWindow Frame GitMenuBar.MainWindow' '0 0 1200 720 0 0 1440 900'
defaults write "$BUNDLE_ID" inspectorColumnWidth -float 720

if ! "$PROJECT_ROOT/scripts/xcodebuild-safe.sh" \
    --project "$PROJECT_ROOT/GitMenuBar.xcodeproj" \
    --scheme GitMenuBar \
    --configuration Debug \
    --derived-data "$DERIVED_DATA" \
    --destination 'platform=macOS' \
    --action build \
    -- PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" >"$LOG_PATH" 2>&1; then
    fail 'debug build failed'
fi

[[ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]] || fail 'built executable is missing'
printf 'RUNTIME_SMOKE: SEEDED window-defaults bundle=%s\n' "$BUNDLE_ID"

HOME="$HOME_ROOT" "$APP_PATH/Contents/MacOS/$APP_NAME" >"$LOG_PATH" 2>&1 &
PID=$!

for _ in $(seq 1 "$STARTUP_TIMEOUT"); do
    if ! kill -0 "$PID" 2>/dev/null; then
        wait "$PID" 2>/dev/null || true
        fail 'app exited during startup'
    fi
    sleep 1
done

for _ in $(seq 1 "$STABILITY_SECONDS"); do
    kill -0 "$PID" 2>/dev/null || fail 'app exited during stability window'
    sleep 1
done

printf 'RUNTIME_SMOKE: PASS window-launch stability=%ss\n' "$STABILITY_SECONDS"
