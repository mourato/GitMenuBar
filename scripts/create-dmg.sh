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

resolve_signing_identity() {
    if [[ -n "${GITMENUBAR_CODE_SIGN_IDENTITY:-}" ]]; then
        printf '%s\n' "${GITMENUBAR_CODE_SIGN_IDENTITY}"
        return 0
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '
            /"Developer ID Application:/ { print $2; found = 1; exit }
            /"Prisma Local Code Signing"/ && local == "" { local = $2 }
            /"Apple Development:/ && development == "" { development = $2 }
            fallback == "" { fallback = $2 }
            END {
                if (found) {
                    exit
                }
                if (local != "") {
                    print local
                } else if (development != "") {
                    print development
                } else if (fallback != "") {
                    print fallback
                }
            }
        '
}

mkdir -p "${DIST_DIR}"

"${PROJECT_DIR}/scripts/run-build.sh" --configuration Release

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Release app bundle not found at: ${APP_BUNDLE}" >&2
    exit 1
fi

SIGNING_IDENTITY="$(resolve_signing_identity)"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "Signing app with: ${SIGNING_IDENTITY}"
    codesign --force --deep --options runtime --timestamp=none --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
    if [[ "${SIGNING_IDENTITY}" != Developer\ ID\ Application:* ]]; then
        echo "Warning: ${SIGNING_IDENTITY} is valid for local development, but Gatekeeper distribution requires a notarized Developer ID Application build." >&2
    fi
else
    echo "No codesigning identity found; DMG will contain an ad-hoc signed app." >&2
fi

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

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "Signing DMG with: ${SIGNING_IDENTITY}"
    codesign --force --timestamp=none --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
fi

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
