#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"

DERIVED_DATA="${PROJECT_ROOT}/.xcode-build-tests"
LOG_PATH="/tmp/gitmenubar-test.log"
BUNDLE_PATH="${DERIVED_DATA}/Build/Products/Debug/GitMenuBarTests.xctest"

echo "Running tests (build-for-testing + xctest)..."
"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --project "${PROJECT_ROOT}/${XCODEPROJ_NAME}" \
    --scheme "${APP_SCHEME}" \
    --configuration Debug \
    --derived-data "${DERIVED_DATA}" \
    --destination "platform=macOS,arch=$(uname -m)" \
    --action build-for-testing >"${LOG_PATH}" 2>&1 || {
        echo "Build-for-testing failed. Log: ${LOG_PATH}" >&2
        rg -n "error:|fatal error:|Test Suite|Failing tests" "${LOG_PATH}" | head -50 || true
        exit 1
    }

if [[ ! -d "${BUNDLE_PATH}" ]]; then
    echo "Test bundle not found at ${BUNDLE_PATH}" >&2
    exit 1
fi

xcrun xctest "${BUNDLE_PATH}" >"${LOG_PATH}" 2>&1 || {
    echo "Tests failed. Log: ${LOG_PATH}" >&2
    rg -n "error:|fatal error:|Test Suite|Failing tests|Assertion|failed" "${LOG_PATH}" | head -80 || true
    exit 1
}

echo "Tests passed"
