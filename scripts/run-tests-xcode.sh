#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config/app_identity.sh"

TEST_PARALLEL="${TEST_PARALLEL:-}"
TEST_WORKERS="${TEST_WORKERS:-}"
TEST_FILTER="${TEST_FILTER:-}"

if [[ -n "${TEST_PARALLEL}" ]]; then
    if [[ "${TEST_PARALLEL}" != "YES" && "${TEST_PARALLEL}" != "NO" ]]; then
        echo "TEST_PARALLEL must be YES, NO, or empty (got '${TEST_PARALLEL}')" >&2
        exit 2
    fi
fi

if [[ -n "${TEST_WORKERS}" ]]; then
    if ! [[ "${TEST_WORKERS}" =~ ^[1-9][0-9]*$ ]]; then
        echo "TEST_WORKERS must be a positive integer (got '${TEST_WORKERS}')" >&2
        exit 2
    fi
fi

TEST_FILTER_ARG=""
if [[ -n "${TEST_FILTER}" ]]; then
    TEST_FILTER="${TEST_FILTER#-only-testing:}"
    [[ -n "${TEST_FILTER}" ]] || { echo "TEST_FILTER cannot be empty" >&2; exit 2; }
    TEST_FILTER_ARG="-only-testing:${TEST_FILTER}"
fi

DERIVED_DATA="${VALIDATE_DERIVED_DATA_PATH:-${PROJECT_ROOT}/.xcode-build-tests}"

RUN_PARENT="${PROJECT_ROOT}/.xcode-build-tests"
if ! mkdir -p "${RUN_PARENT}" 2>/dev/null; then
    RUN_PARENT="${TMPDIR:-/tmp}"
fi
RUN_DIR="$(mktemp -d "${RUN_PARENT}/test-run.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/gitmenubar-test-run.XXXXXX")"

BUILD_LOG="${RUN_DIR}/build-for-testing.log"
TEST_LOG="${RUN_DIR}/test-without-building.log"
RESULT_BUNDLE_PATH="${RUN_DIR}/TestResults.xcresult"

echo "Test run directory: ${RUN_DIR}"
echo "Build log:          ${BUILD_LOG}"
echo "Test log:           ${TEST_LOG}"
echo "Result bundle:      ${RESULT_BUNDLE_PATH}"

if [[ -n "${TEST_FILTER_ARG}" ]]; then
    echo "Running focused tests: ${TEST_FILTER}..."
else
    echo "Running tests (build-for-testing + test-without-building)..."
fi

status=0
"${SCRIPT_DIR}/xcodebuild-safe.sh" \
    --project "${PROJECT_ROOT}/${XCODEPROJ_NAME}" \
    --scheme "${APP_SCHEME}" \
    --configuration Debug \
    --derived-data "${DERIVED_DATA}" \
    --destination "platform=macOS,arch=$(uname -m)" \
    --action build-for-testing >"${BUILD_LOG}" 2>&1 || status=$?

if [[ ${status} -ne 0 ]]; then
    echo "Build-for-testing failed (exit ${status})." >&2
    echo "Run directory: ${RUN_DIR}" >&2
    echo "Build log:     ${BUILD_LOG}" >&2
    echo "Result bundle: ${RESULT_BUNDLE_PATH}" >&2
    rg -n "error:|fatal error:|Test Suite|Failing tests" "${BUILD_LOG}" 2>/dev/null | head -50 >&2 || true
    exit "${status}"
fi

TEST_COMMAND_ARGS=(
    --project "${PROJECT_ROOT}/${XCODEPROJ_NAME}"
    --scheme "${APP_SCHEME}"
    --configuration Debug
    --derived-data "${DERIVED_DATA}"
    --destination "platform=macOS,arch=$(uname -m)"
    --action test-without-building
    --
    -resultBundlePath "${RESULT_BUNDLE_PATH}"
)

if [[ -n "${TEST_PARALLEL}" ]]; then
    TEST_COMMAND_ARGS+=( -parallel-testing-enabled "${TEST_PARALLEL}" )
fi

if [[ -n "${TEST_WORKERS}" ]]; then
    TEST_COMMAND_ARGS+=( -maximum-parallel-testing-workers "${TEST_WORKERS}" )
fi

if [[ -n "${TEST_FILTER_ARG}" ]]; then
    TEST_COMMAND_ARGS+=( "${TEST_FILTER_ARG}" )
fi

status=0
"${SCRIPT_DIR}/xcodebuild-safe.sh" "${TEST_COMMAND_ARGS[@]}" >"${TEST_LOG}" 2>&1 || status=$?

if [[ ${status} -ne 0 ]]; then
    echo "Tests failed (exit ${status})." >&2
    echo "Run directory: ${RUN_DIR}" >&2
    echo "Build log:     ${BUILD_LOG}" >&2
    echo "Test log:      ${TEST_LOG}" >&2
    echo "Result bundle: ${RESULT_BUNDLE_PATH}" >&2
    rg -n "error:|fatal error:|Test Suite|Failing tests|Assertion|failed" "${TEST_LOG}" 2>/dev/null | head -80 >&2 || true
    exit "${status}"
fi

echo "Tests passed"
echo "Run directory: ${RUN_DIR}"
echo "Build log:     ${BUILD_LOG}"
echo "Test log:      ${TEST_LOG}"
echo "Result bundle: ${RESULT_BUNDLE_PATH}"
