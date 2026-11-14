#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"
source "${SCRIPT_DIR}/config/release_signing.sh"

CONFIGURATION="Debug"
DERIVED_DATA="${VALIDATE_DERIVED_DATA_PATH:-${PROJECT_ROOT}/.xcode-build}"
DEVELOPMENT_TEAM="${GITMENUBAR_DEVELOPMENT_TEAM:-}"
XCODEBUILD_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration|-c)
            CONFIGURATION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--configuration Debug|Release]"
            echo ""
            echo "Environment:"
            echo "  GITMENUBAR_CODE_SIGN_IDENTITY  Identity for local builds (default: Apple Development)"
            echo "  GITMENUBAR_DEVELOPMENT_TEAM    Sign through Xcode with this team and the keychain access group"
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

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    # Xcode signs with the provisioning profile of this team, which is the only way to
    # embed the keychain access group entitlement.
    XCODEBUILD_EXTRA_ARGS+=(
        "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}"
        "CODE_SIGN_ENTITLEMENTS=${PROJECT_ROOT}/GitMenuBar/GitMenuBar-KeychainAccessGroups.entitlements"
    )
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
    --action build \
    -- ${XCODEBUILD_EXTRA_ARGS[@]+"${XCODEBUILD_EXTRA_ARGS[@]}"} >"${LOG_PATH}" 2>&1 || {
        echo "Build failed. Log: ${LOG_PATH}" >&2
        rg -n "error:|BUILD FAILED" "${LOG_PATH}" | head -30 || true
        exit 1
    }

echo "Build succeeded"
PRODUCTS_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"
APP_BUNDLE_PATH="${PRODUCTS_DIR}/${APP_PRODUCT_NAME}.app"
APP_EXEC_PATH="${APP_BUNDLE_PATH}/Contents/MacOS/${APP_PRODUCT_NAME}"

if [[ ! -x "${APP_EXEC_PATH}" ]]; then
    echo "App executable missing: ${APP_EXEC_PATH}" >&2
    exit 1
fi

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    echo "Signed by Xcode with DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}"
else
    # One stable identity for Debug and Release builds, so the keychain keeps granting
    # "Always allow" across rebuilds and reinstalls.
    gitmenubar_sign_app_bundle "${APP_BUNDLE_PATH}"
    codesign --verify --strict "${APP_BUNDLE_PATH}"
fi
