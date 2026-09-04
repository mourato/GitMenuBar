#!/bin/bash

set -euo pipefail

GITMENUBAR_RELEASE_SIGNING_MODE_WAS_SET=0
if [ "${GITMENUBAR_RELEASE_SIGNING_MODE+x}" = "x" ]; then
    GITMENUBAR_RELEASE_SIGNING_MODE_WAS_SET=1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_DIR}/scripts/config/app_identity.sh"
# shellcheck source=scripts/config/release_signing.sh
source "${PROJECT_DIR}/scripts/config/release_signing.sh"

DIST_DIR="${PROJECT_DIR}/dist"
DERIVED_DATA="${PROJECT_DIR}/.xcode-build"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release/${APP_PRODUCT_NAME}.app"
STAGING_DIR="${DIST_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_PRODUCT_NAME}.dmg"
VOLUME_NAME="${APP_PRODUCT_NAME}"

CI_MODE=0
NO_INTERACTIVE=0
AUTO_SIGNING=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

prompt_select_keychain_identity() {
    local identities=()
    local i=1
    local identity=""
    local choice=""

    while IFS= read -r identity; do
        [ -n "$identity" ] && identities+=("$identity")
    done < <(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/ { print $2 }' | awk '!seen[$0]++')

    if [ "${#identities[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No code signing identities found in Keychain. Falling back to adhoc.${NC}"
        GITMENUBAR_RELEASE_SIGNING_MODE="adhoc"
        return 0
    fi

    echo -e "${YELLOW}Available Keychain identities:${NC}"
    for identity in "${identities[@]}"; do
        echo "  ${i}) ${identity}"
        i=$((i + 1))
    done

    printf "Select identity [1-%d] (default: 1): " "${#identities[@]}"
    read -r choice < /dev/tty || choice="1"
    choice="${choice:-1}"

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#identities[@]}" ]; then
        local selected_idx=$((choice - 1))
        GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY="${identities[$selected_idx]}"
        GITMENUBAR_RELEASE_SIGNING_MODE="self-signed"
        echo -e "${GREEN}Selected:${NC} ${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"
    else
        echo -e "${RED}Invalid selection. Using adhoc.${NC}"
        GITMENUBAR_RELEASE_SIGNING_MODE="adhoc"
    fi
}

prompt_release_signing_mode() {
    local detected_mode=""
    local default_choice="1"
    local reply=""

    detected_mode="$(gitmenubar_autodetect_release_signing_mode)"

    echo -e "${YELLOW}Select DMG signing mode:${NC}"
    if [ "${detected_mode}" = "self-signed" ]; then
        echo "  1) Auto (default): use self-signed because '${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}' is available"
    else
        echo "  1) Auto (default): use adhoc because '${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}' is not available"
    fi
    echo "  2) Self-signed (${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY})"
    echo "  3) Choose from available Keychain certificates"
    echo "  4) Adhoc"
    printf "Choose [1/2/3/4] (default: %s): " "${default_choice}"
    read -r reply < /dev/tty || reply=""
    echo ""

    case "${reply:-${default_choice}}" in
        1)
            GITMENUBAR_RELEASE_SIGNING_MODE="${detected_mode}"
            ;;
        2)
            GITMENUBAR_RELEASE_SIGNING_MODE="self-signed"
            ;;
        3)
            prompt_select_keychain_identity
            ;;
        4)
            GITMENUBAR_RELEASE_SIGNING_MODE="adhoc"
            ;;
        *)
            echo -e "${RED}Invalid selection: ${reply}${NC}" >&2
            return 1
            ;;
    esac

    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci)
            CI_MODE=1
            shift
            ;;
        --no-interactive)
            NO_INTERACTIVE=1
            shift
            ;;
        --auto-signing)
            AUTO_SIGNING=1
            shift
            ;;
        --signing-mode)
            GITMENUBAR_RELEASE_SIGNING_MODE="$2"
            GITMENUBAR_RELEASE_SIGNING_MODE_WAS_SET=1
            shift 2
            ;;
        --sign-identity)
            GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: scripts/create-dmg.sh [options]

Options:
  --ci                          Run in CI mode (no prompts)
  --no-interactive              Run without interactive prompts
  --auto-signing                Auto-detect signing mode from keychain identity
  --signing-mode MODE           Explicit mode: 'adhoc' or 'self-signed'
  --sign-identity IDENTITY      Custom signing identity name
  --help                        Show this help
USAGE
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

if [ "${CI_MODE}" -eq 1 ] || [ "${NO_INTERACTIVE}" -eq 1 ]; then
    INTERACTIVE=0
else
    INTERACTIVE=1
fi

if [ "${GITMENUBAR_RELEASE_SIGNING_MODE_WAS_SET}" -eq 0 ]; then
    if [ "${INTERACTIVE}" -eq 1 ]; then
        if ! prompt_release_signing_mode; then
            exit 1
        fi
    elif [ "${AUTO_SIGNING}" -eq 1 ]; then
        GITMENUBAR_RELEASE_SIGNING_MODE="$(gitmenubar_autodetect_release_signing_mode)"
    fi
fi

if ! gitmenubar_validate_release_signing_mode; then
    exit 1
fi

if ! gitmenubar_require_self_signed_identity; then
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Creating ${APP_PRODUCT_NAME}.dmg${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Release signing mode:${NC} $(gitmenubar_release_signing_description)"

mkdir -p "${DIST_DIR}"

echo -e "${YELLOW}Building Release version...${NC}"
"${PROJECT_DIR}/scripts/run-build.sh" --configuration Release

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo -e "${RED}Release app bundle not found at: ${APP_BUNDLE}${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Code signing app bundle...${NC}"
if [ "${GITMENUBAR_RELEASE_SIGNING_MODE}" = "self-signed" ]; then
    echo "Signing app with '${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}'..."
    codesign --force --deep --keychain "${HOME}/Library/Keychains/login.keychain-db" --timestamp=none --sign "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}" "${APP_BUNDLE}"
else
    echo "Signing app ad-hoc for local DMG installation."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
    -srcfolder "${STAGING_DIR}" \
    -volname "${VOLUME_NAME}" \
    -fs HFS+ \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo -e "${YELLOW}Code signing DMG...${NC}"
if [ "${GITMENUBAR_RELEASE_SIGNING_MODE}" = "self-signed" ]; then
    codesign --force --keychain "${HOME}/Library/Keychains/login.keychain-db" --timestamp=none --sign "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}" "${DMG_PATH}"
else
    codesign --force --sign - "${DMG_PATH}"
fi
codesign --verify --verbose=2 "${DMG_PATH}"

echo -e "${GREEN}✓ DMG created successfully: ${DMG_PATH}${NC}"

if [ "${INTERACTIVE}" -eq 1 ] && [ -t 0 ]; then
    printf "Open DMG now? [y/N] "
    read -r open_dmg < /dev/tty || open_dmg=""

    case "${open_dmg}" in
        y|Y)
            open "${DMG_PATH}"
            ;;
    esac
fi
