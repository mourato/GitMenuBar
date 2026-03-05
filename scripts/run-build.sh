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
