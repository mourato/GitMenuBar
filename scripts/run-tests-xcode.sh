#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"

DERIVED_DATA="${VALIDATE_DERIVED_DATA_PATH:-${PROJECT_ROOT}/.xcode-build-tests}"
TEST_FILTER="${TEST_FILTER:-}"
LOG_PATH="/tmp/gitmenubar-test.log"
TEST_OPTIONS=()
if [[ -n "${TEST_FILTER}" ]]; then
    TEST_FILTER="${TEST_FILTER#-only-testing:}"
    [[ -n "${TEST_FILTER}" ]] || { echo "TEST_FILTER cannot be empty" >&2; exit 2; }
    TEST_OPTIONS+=(-- "-only-testing:${TEST_FILTER}")
    echo "Running focused tests: ${TEST_FILTER}..."
else
    echo "Running tests (build-for-testing + test-without-building)..."
fi
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

"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --project "${PROJECT_ROOT}/${XCODEPROJ_NAME}" \
    --scheme "${APP_SCHEME}" \
    --configuration Debug \
    --derived-data "${DERIVED_DATA}" \
    --destination "platform=macOS,arch=$(uname -m)" \
    --action test-without-building "${TEST_OPTIONS[@]}" >"${LOG_PATH}" 2>&1 || {
    echo "Tests failed. Log: ${LOG_PATH}" >&2
    rg -n "error:|fatal error:|Test Suite|Failing tests|Assertion|failed" "${LOG_PATH}" | head -80 || true
    exit 1
}

echo "Tests passed"
