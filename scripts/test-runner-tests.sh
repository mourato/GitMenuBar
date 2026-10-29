#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HARNESS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-runner-harness.XXXXXX")"
cleanup() {
    rm -rf "${HARNESS_TMP}"
}
trap cleanup EXIT

STUB_BIN_DIR="${HARNESS_TMP}/bin"
STUB_STATE_DIR="${HARNESS_TMP}/state"
mkdir -p "${STUB_BIN_DIR}" "${STUB_STATE_DIR}"

STUB_XCODEBUILD="${STUB_BIN_DIR}/xcodebuild"
cat << 'EOF' > "${STUB_XCODEBUILD}"
#!/bin/bash
set -eu

STATE_DIR="${STUB_STATE_DIR}"
INVOCATIONS_FILE="${STATE_DIR}/invocations.txt"

# Record raw arguments
echo "INVOCATION: $*" >> "${INVOCATIONS_FILE}"

ACTION=""
RESULT_BUNDLE=""
DERIVED_DATA=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -action)
            ACTION="$2"
            shift 2
            ;;
        -resultBundlePath)
            RESULT_BUNDLE="$2"
            shift 2
            ;;
        -derivedDataPath)
            DERIVED_DATA="$2"
            shift 2
            ;;
        build-for-testing|test-without-building)
            ACTION="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -n "${RESULT_BUNDLE}" ]]; then
    if [[ -e "${RESULT_BUNDLE}" ]]; then
        echo "PRECREATED: ${RESULT_BUNDLE}" >> "${STATE_DIR}/precreated.txt"
    fi
fi

if [[ "${ACTION}" == "build-for-testing" ]]; then
    echo "=== Staged build-for-testing ==="
    BUILD_EXIT="${STUB_BUILD_EXIT:-0}"
    if [[ "${BUILD_EXIT}" -ne 0 ]]; then
        echo "error: build failed with code ${BUILD_EXIT}" >&2
        exit "${BUILD_EXIT}"
    fi
    echo "** BUILD FOR TESTING SUCCEEDED **"
    exit 0
elif [[ "${ACTION}" == "test-without-building" ]]; then
    echo "=== Staged test-without-building ==="
    if [[ -n "${RESULT_BUNDLE}" ]]; then
        # Simulate xcodebuild creating the bundle
        mkdir -p "${RESULT_BUNDLE}"
        touch "${RESULT_BUNDLE}/Info.plist"
    fi
    TEST_EXIT="${STUB_TEST_EXIT:-0}"
    if [[ "${TEST_EXIT}" -ne 0 ]]; then
        echo "Failing tests: SomeTestClass.testFailure" >&2
        echo "Assertion failed: expected true, got false" >&2
        exit "${TEST_EXIT}"
    fi
    echo "** TEST WITHOUT BUILDING SUCCEEDED **"
    exit 0
fi

exit 0
EOF
chmod +x "${STUB_XCODEBUILD}"

RUNNER="${SCRIPT_DIR}/run-tests-xcode.sh"

reset_stub() {
    rm -rf "${STUB_STATE_DIR}"
    mkdir -p "${STUB_STATE_DIR}"
    : > "${STUB_STATE_DIR}/invocations.txt"
}

PASSED_TESTS=0

pass() {
    local name="$1"
    echo "PASS: ${name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

fail() {
    local name="$1"
    local reason="$2"
    echo "FAIL: ${name} - ${reason}" >&2
    exit 1
}

export PATH="${STUB_BIN_DIR}:${PATH}"
export STUB_STATE_DIR

# -----------------------------------------------------------------------------
# Proof 1: default unchanged flags
# -----------------------------------------------------------------------------
reset_stub
export STUB_BUILD_EXIT=0
export STUB_TEST_EXIT=0
OUTPUT=$(TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" 2>&1) || fail "default unchanged flags" "runner failed: ${OUTPUT}"

INVOCATIONS=$(cat "${STUB_STATE_DIR}/invocations.txt")
BUILD_INVOCATION=$(echo "${INVOCATIONS}" | grep "build-for-testing" || true)
TEST_INVOCATION=$(echo "${INVOCATIONS}" | grep "test-without-building" || true)

[[ -n "${BUILD_INVOCATION}" ]] || fail "default unchanged flags" "missing build-for-testing invocation"
[[ -n "${TEST_INVOCATION}" ]] || fail "default unchanged flags" "missing test-without-building invocation"

if echo "${BUILD_INVOCATION}" | grep -q -- "-parallel-testing-enabled"; then
    fail "default unchanged flags" "build-for-testing unexpectedly received -parallel-testing-enabled"
fi
if echo "${BUILD_INVOCATION}" | grep -q -- "-maximum-parallel-testing-workers"; then
    fail "default unchanged flags" "build-for-testing unexpectedly received -maximum-parallel-testing-workers"
fi
if echo "${BUILD_INVOCATION}" | grep -q -- "-resultBundlePath"; then
    fail "default unchanged flags" "build-for-testing unexpectedly received -resultBundlePath"
fi

if echo "${TEST_INVOCATION}" | grep -q -- "-parallel-testing-enabled"; then
    fail "default unchanged flags" "test-without-building unexpectedly received -parallel-testing-enabled"
fi
if echo "${TEST_INVOCATION}" | grep -q -- "-maximum-parallel-testing-workers"; then
    fail "default unchanged flags" "test-without-building unexpectedly received -maximum-parallel-testing-workers"
fi
if echo "${TEST_INVOCATION}" | grep -q -- "-only-testing"; then
    fail "default unchanged flags" "test-without-building unexpectedly received -only-testing"
fi
if ! echo "${TEST_INVOCATION}" | grep -q -- "-resultBundlePath"; then
    fail "default unchanged flags" "test-without-building missing -resultBundlePath"
fi
pass "default unchanged flags"

# -----------------------------------------------------------------------------
# Proof 2: serialNO
# -----------------------------------------------------------------------------
reset_stub
OUTPUT=$(TEST_PARALLEL="NO" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" 2>&1) || fail "serialNO" "runner failed: ${OUTPUT}"
TEST_INVOCATION=$(grep "test-without-building" "${STUB_STATE_DIR}/invocations.txt" || true)

if ! echo "${TEST_INVOCATION}" | grep -q -- "-parallel-testing-enabled NO"; then
    fail "serialNO" "test-without-building missing '-parallel-testing-enabled NO'"
fi
if echo "${TEST_INVOCATION}" | grep -q -- "-maximum-parallel-testing-workers"; then
    fail "serialNO" "serial run unexpectedly received -maximum-parallel-testing-workers"
fi
pass "serialNO"

# -----------------------------------------------------------------------------
# Proof 3: parallelYES workers2
# -----------------------------------------------------------------------------
reset_stub
OUTPUT=$(TEST_PARALLEL="YES" TEST_WORKERS="2" TEST_FILTER="" "${RUNNER}" 2>&1) || fail "parallelYES workers2" "runner failed: ${OUTPUT}"
TEST_INVOCATION=$(grep "test-without-building" "${STUB_STATE_DIR}/invocations.txt" || true)

if ! echo "${TEST_INVOCATION}" | grep -q -- "-parallel-testing-enabled YES"; then
    fail "parallelYES workers2" "test-without-building missing '-parallel-testing-enabled YES'"
fi
if ! echo "${TEST_INVOCATION}" | grep -q -- "-maximum-parallel-testing-workers 2"; then
    fail "parallelYES workers2" "test-without-building missing '-maximum-parallel-testing-workers 2'"
fi
pass "parallelYES workers2"

# -----------------------------------------------------------------------------
# Proof 4: exact TEST_FILTER
# -----------------------------------------------------------------------------
reset_stub
OUTPUT=$(TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="GitMenuBarTests/SpecificTest" "${RUNNER}" 2>&1) || fail "exact TEST_FILTER" "runner failed: ${OUTPUT}"
TEST_INVOCATION=$(grep "test-without-building" "${STUB_STATE_DIR}/invocations.txt" || true)

if ! echo "${TEST_INVOCATION}" | grep -q -- "-only-testing:GitMenuBarTests/SpecificTest"; then
    fail "exact TEST_FILTER" "test-without-building missing '-only-testing:GitMenuBarTests/SpecificTest'"
fi

reset_stub
OUTPUT=$(TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="-only-testing:GitMenuBarTests/PrefixedTest" "${RUNNER}" 2>&1) || fail "exact TEST_FILTER (prefixed)" "runner failed: ${OUTPUT}"
TEST_INVOCATION=$(grep "test-without-building" "${STUB_STATE_DIR}/invocations.txt" || true)

if ! echo "${TEST_INVOCATION}" | grep -q -- "-only-testing:GitMenuBarTests/PrefixedTest"; then
    fail "exact TEST_FILTER (prefixed)" "test-without-building missing '-only-testing:GitMenuBarTests/PrefixedTest'"
fi
pass "exact TEST_FILTER"

# -----------------------------------------------------------------------------
# Proof 5: paths unique concurrent runs (distinct deriveddata overrides)
# -----------------------------------------------------------------------------
reset_stub
DD_OVERRIDE_1="${HARNESS_TMP}/dd1"
DD_OVERRIDE_2="${HARNESS_TMP}/dd2"
mkdir -p "${DD_OVERRIDE_1}" "${DD_OVERRIDE_2}"

RUN1_OUT="${HARNESS_TMP}/run1.out"
RUN2_OUT="${HARNESS_TMP}/run2.out"

(VALIDATE_DERIVED_DATA_PATH="${DD_OVERRIDE_1}" TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" > "${RUN1_OUT}" 2>&1) &
PID1=$!
(VALIDATE_DERIVED_DATA_PATH="${DD_OVERRIDE_2}" TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" > "${RUN2_OUT}" 2>&1) &
PID2=$!

wait "${PID1}" || fail "paths unique concurrent runs" "run 1 failed: $(cat "${RUN1_OUT}")"
wait "${PID2}" || fail "paths unique concurrent runs" "run 2 failed: $(cat "${RUN2_OUT}")"

RUN1_DIR=$(grep "Test run directory:" "${RUN1_OUT}" | head -1 | awk '{print $NF}')
RUN2_DIR=$(grep "Test run directory:" "${RUN2_OUT}" | head -1 | awk '{print $NF}')

[[ -n "${RUN1_DIR}" ]] || fail "paths unique concurrent runs" "missing RUN1_DIR"
[[ -n "${RUN2_DIR}" ]] || fail "paths unique concurrent runs" "missing RUN2_DIR"

if [[ "${RUN1_DIR}" == "${RUN2_DIR}" ]]; then
    fail "paths unique concurrent runs" "run directories collided: ${RUN1_DIR}"
fi

RUN1_BUNDLE=$(grep "Result bundle:" "${RUN1_OUT}" | head -1 | awk '{print $NF}')
RUN2_BUNDLE=$(grep "Result bundle:" "${RUN2_OUT}" | head -1 | awk '{print $NF}')

if [[ "${RUN1_BUNDLE}" == "${RUN2_BUNDLE}" ]]; then
    fail "paths unique concurrent runs" "result bundles collided: ${RUN1_BUNDLE}"
fi

INVOCATIONS=$(cat "${STUB_STATE_DIR}/invocations.txt")
if ! echo "${INVOCATIONS}" | grep -q -- "-derivedDataPath ${DD_OVERRIDE_1}"; then
    fail "paths unique concurrent runs" "missing derivedDataPath override 1"
fi
if ! echo "${INVOCATIONS}" | grep -q -- "-derivedDataPath ${DD_OVERRIDE_2}"; then
    fail "paths unique concurrent runs" "missing derivedDataPath override 2"
fi
pass "paths unique concurrent runs (distinct deriveddata overrides)"

# -----------------------------------------------------------------------------
# Proof 6: build log retained
# -----------------------------------------------------------------------------
reset_stub
OUT_LOGS="${HARNESS_TMP}/logs_proof.out"
TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" > "${OUT_LOGS}" 2>&1 || fail "build log retained" "runner failed"

PROOF_RUN_DIR=$(grep "Test run directory:" "${OUT_LOGS}" | head -1 | awk '{print $NF}')
BUILD_LOG_FILE="${PROOF_RUN_DIR}/build-for-testing.log"
TEST_LOG_FILE="${PROOF_RUN_DIR}/test-without-building.log"

[[ -f "${BUILD_LOG_FILE}" ]] || fail "build log retained" "build log file does not exist at ${BUILD_LOG_FILE}"
[[ -f "${TEST_LOG_FILE}" ]] || fail "build log retained" "test log file does not exist at ${TEST_LOG_FILE}"

if ! grep -q "BUILD FOR TESTING SUCCEEDED" "${BUILD_LOG_FILE}"; then
    fail "build log retained" "build log does not contain build output (may have been overwritten)"
fi
if ! grep -q "TEST WITHOUT BUILDING SUCCEEDED" "${TEST_LOG_FILE}"; then
    fail "build log retained" "test log missing test output"
fi
pass "build log retained"

# -----------------------------------------------------------------------------
# Proof 7: build failure70 no testphase
# -----------------------------------------------------------------------------
reset_stub
export STUB_BUILD_EXIT=70
export STUB_TEST_EXIT=0
ERR_OUT="${HARNESS_TMP}/build_fail.out"
set +e
TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" > "${ERR_OUT}" 2>&1
ACTUAL_EXIT=$?
set -e

if [[ "${ACTUAL_EXIT}" -ne 70 ]]; then
    fail "build failure70 no testphase" "expected exit code 70, got ${ACTUAL_EXIT}. Output: $(cat "${ERR_OUT}")"
fi

if grep -q "test-without-building" "${STUB_STATE_DIR}/invocations.txt"; then
    fail "build failure70 no testphase" "test phase was invoked after build failure"
fi

if ! grep -q "Build-for-testing failed (exit 70)" "${ERR_OUT}"; then
    fail "build failure70 no testphase" "stderr missing build failure announcement"
fi
pass "build failure70 no testphase"

# -----------------------------------------------------------------------------
# Proof 8: test failure65
# -----------------------------------------------------------------------------
reset_stub
export STUB_BUILD_EXIT=0
export STUB_TEST_EXIT=65
ERR_OUT="${HARNESS_TMP}/test_fail.out"
set +e
TEST_PARALLEL="" TEST_WORKERS="" TEST_FILTER="" "${RUNNER}" > "${ERR_OUT}" 2>&1
ACTUAL_EXIT=$?
set -e

if [[ "${ACTUAL_EXIT}" -ne 65 ]]; then
    fail "test failure65" "expected exit code 65, got ${ACTUAL_EXIT}. Output: $(cat "${ERR_OUT}")"
fi

if ! grep -q "Tests failed (exit 65)" "${ERR_OUT}"; then
    fail "test failure65" "stderr missing test failure announcement"
fi

# Ensure build log is still preserved even when test fails
TEST_FAIL_RUN_DIR=$(grep "Test run directory:" "${ERR_OUT}" | head -1 | awk '{print $NF}')
[[ -f "${TEST_FAIL_RUN_DIR}/build-for-testing.log" ]] || fail "test failure65" "build log missing on test failure"
grep -q "BUILD FOR TESTING SUCCEEDED" "${TEST_FAIL_RUN_DIR}/build-for-testing.log" || fail "test failure65" "build log incomplete on test failure"
pass "test failure65"

# -----------------------------------------------------------------------------
# Proof 9: invalid options exit2 before xcode
# -----------------------------------------------------------------------------
check_invalid_option() {
    local env_var="$1"
    local value="$2"
    local label="$3"

    reset_stub
    local out="${HARNESS_TMP}/invalid.out"
    set +e
    env "${env_var}=${value}" "${RUNNER}" > "${out}" 2>&1
    local code=$?
    set -e

    if [[ "${code}" -ne 2 ]]; then
        fail "invalid options exit2 before xcode (${label})" "expected exit 2, got ${code}. Output: $(cat "${out}")"
    fi

    if [[ -s "${STUB_STATE_DIR}/invocations.txt" ]]; then
        fail "invalid options exit2 before xcode (${label})" "xcodebuild was called despite invalid option"
    fi
}

check_invalid_option "TEST_PARALLEL" "MAYBE" "TEST_PARALLEL=MAYBE"
check_invalid_option "TEST_PARALLEL" "1" "TEST_PARALLEL=1"
check_invalid_option "TEST_WORKERS" "0" "TEST_WORKERS=0"
check_invalid_option "TEST_WORKERS" "-2" "TEST_WORKERS=-2"
check_invalid_option "TEST_WORKERS" "xyz" "TEST_WORKERS=xyz"
check_invalid_option "TEST_FILTER" "-only-testing:" "TEST_FILTER=-only-testing:"
pass "invalid options exit2 before xcode"

# -----------------------------------------------------------------------------
# Proof 10: result bundle path not precreated
# -----------------------------------------------------------------------------
if [[ -f "${STUB_STATE_DIR}/precreated.txt" ]]; then
    fail "result bundle path not precreated" "result bundle existed before xcodebuild ran: $(cat "${STUB_STATE_DIR}/precreated.txt")"
fi
pass "result bundle path not precreated"

echo "========================================"
echo "All ${PASSED_TESTS} test runner regression checks passed!"
echo "========================================"
exit 0
