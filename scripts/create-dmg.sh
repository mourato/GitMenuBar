#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${PROJECT_DIR}/scripts/config/app_identity.sh"

DIST_DIR="${PROJECT_DIR}/dist"
DERIVED_DATA="${PROJECT_DIR}/.xcode-build"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release/${APP_PRODUCT_NAME}.app"
STAGING_DIR="${DIST_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_PRODUCT_NAME}.dmg"
VOLUME_NAME="${APP_PRODUCT_NAME}"

mkdir -p "${DIST_DIR}"

"${PROJECT_DIR}/scripts/run-build.sh" --configuration Release

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Release app bundle not found at: ${APP_BUNDLE}" >&2
    exit 1
fi

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "DMG created: ${DMG_PATH}"

if [[ -t 0 ]]; then
    printf "Open DMG now? [y/N] "
    read -r open_dmg < /dev/tty || open_dmg=""

    case "${open_dmg}" in
        y|Y)
            open "${DMG_PATH}"
            ;;
    esac
fi
