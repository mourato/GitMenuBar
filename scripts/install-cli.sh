#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"

INSTALL_DIR="${HOME}/.local/bin"
LINK_PATH="${INSTALL_DIR}/gitmenubar"
APP_BUNDLE_NAME="${APP_PRODUCT_NAME}.app"
CLI_RELATIVE="Contents/MacOS/gitmenubar"

find_cli_in_app() {
    local app_path="$1"
    local cli="${app_path}/${CLI_RELATIVE}"
    if [[ -x "${cli}" ]]; then
        printf '%s\n' "${cli}"
        return 0
    fi
    return 1
}

SOURCE=""
SEARCH_ORDER=()

PREFERRED_DIST_APP="${PROJECT_ROOT}/dist/${APP_BUNDLE_NAME}"
if [[ -d "${PREFERRED_DIST_APP}" ]]; then
    SEARCH_ORDER+=("${PREFERRED_DIST_APP}")
fi

if [[ -d "${PROJECT_ROOT}/dist" ]]; then
    for app in "${PROJECT_ROOT}/dist/"*.app; do
        [[ -d "${app}" ]] || continue
        [[ "${app}" == "${PREFERRED_DIST_APP}" ]] && continue
        SEARCH_ORDER+=("${app}")
    done
fi

SEARCH_ORDER+=(
    "/Applications/${APP_BUNDLE_NAME}"
    "${PROJECT_ROOT}/.xcode-build/Build/Products/Release/${APP_BUNDLE_NAME}"
    "${PROJECT_ROOT}/.xcode-build/Build/Products/Debug/${APP_BUNDLE_NAME}"
)

for app in "${SEARCH_ORDER[@]}"; do
    if cli="$(find_cli_in_app "${app}" 2>/dev/null || true)"; then
        SOURCE="${cli}"
        break
    fi
done

if [[ -z "${SOURCE}" ]]; then
    echo "Error: Could not find gitmenubar inside ${APP_BUNDLE_NAME}." >&2
    echo "Build or install the app first:" >&2
    echo "  make build          # Debug build in .xcode-build/" >&2
    echo "  make build-release  # Release build in .xcode-build/" >&2
    echo "  make dmg            # Release app in dist/ (preferred stable symlink target)" >&2
    echo "  Copy or install the app to /Applications/${APP_BUNDLE_NAME}" >&2
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [[ -L "${LINK_PATH}" ]]; then
    CURRENT="$(readlink "${LINK_PATH}")"
    if [[ "${CURRENT}" == "${SOURCE}" ]]; then
        echo "Already installed: ${LINK_PATH} -> ${SOURCE}"
        exit 0
    fi
    rm -f "${LINK_PATH}"
elif [[ -e "${LINK_PATH}" ]]; then
    echo "Error: ${LINK_PATH} exists and is not a symlink. Remove it manually, then retry." >&2
    exit 1
fi

ln -sf "${SOURCE}" "${LINK_PATH}"
echo "Installed: ${LINK_PATH} -> ${SOURCE}"
echo "Ensure ~/.local/bin is on your PATH, for example:"
echo '  export PATH="$HOME/.local/bin:$PATH"'

if [[ "${SOURCE}" == *"/.xcode-build/"* ]]; then
    echo "Note: Symlink points at a local build product. Prefer /Applications or dist/ after release install for a stable path." >&2
fi
