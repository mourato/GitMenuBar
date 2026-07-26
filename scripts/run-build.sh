#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"

CONFIGURATION="Debug"
DERIVED_DATA="${PROJECT_ROOT}/.xcode-build"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration|-c)
            CONFIGURATION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--configuration Debug|Release]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ "${CONFIGURATION}" != "Debug" && "${CONFIGURATION}" != "Release" ]]; then
    echo "Invalid configuration: ${CONFIGURATION}" >&2
    exit 1
fi

CONFIG_SLUG="$(echo "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"
LOG_PATH="/tmp/gitmenubar-build-${CONFIG_SLUG}.log"

echo "Building ${APP_PRODUCT_NAME} (${CONFIGURATION})..."
"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --project "${PROJECT_ROOT}/${XCODEPROJ_NAME}" \
    --scheme "${APP_SCHEME}" \
    --configuration "${CONFIGURATION}" \
    --derived-data "${DERIVED_DATA}" \
    --destination 'platform=macOS' \
    --action build >"${LOG_PATH}" 2>&1 || {
        echo "Build failed. Log: ${LOG_PATH}" >&2
        rg -n "error:|BUILD FAILED" "${LOG_PATH}" | head -30 || true
        exit 1
    }

echo "Build succeeded"
PRODUCTS_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"
APP_EXEC_PATH="${PRODUCTS_DIR}/${APP_PRODUCT_NAME}.app/Contents/MacOS/${APP_PRODUCT_NAME}"
CLI_PATH="${PRODUCTS_DIR}/gitmenubar"
BUNDLE_CLI_PATH="${PRODUCTS_DIR}/${APP_PRODUCT_NAME}.app/Contents/Helpers/gitmenubar"

if [[ ! -x "${APP_EXEC_PATH}" ]]; then
    echo "App executable missing: ${APP_EXEC_PATH}" >&2
    exit 1
fi
if [[ -x "${CLI_PATH}" ]] && cmp -s "${CLI_PATH}" "${APP_EXEC_PATH}"; then
    echo "App executable was overwritten by Companion CLI: ${APP_EXEC_PATH}" >&2
    exit 1
fi
# Do not launch the GUI binary for verification (it would hang as a menu-bar app).
if command -v nm >/dev/null 2>&1; then
    if nm -gU "${APP_EXEC_PATH}" 2>/dev/null | grep -q 'GitMenuBarCLI'; then
        echo "App executable still embeds Companion CLI entrypoint: ${APP_EXEC_PATH}" >&2
        exit 1
    fi
fi

if [[ -x "${CLI_PATH}" ]]; then
    echo "Companion CLI: ${CLI_PATH}"
fi
if [[ ! -x "${BUNDLE_CLI_PATH}" ]]; then
    echo "Bundled CLI missing or not executable: ${BUNDLE_CLI_PATH}" >&2
    exit 1
fi
if cmp -s "${BUNDLE_CLI_PATH}" "${APP_EXEC_PATH}"; then
    echo "Bundled CLI path points at the app executable: ${BUNDLE_CLI_PATH}" >&2
    exit 1
fi
echo "Bundled CLI: ${BUNDLE_CLI_PATH}"
"${BUNDLE_CLI_PATH}" --help >/dev/null
