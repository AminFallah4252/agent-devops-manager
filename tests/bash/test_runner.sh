#!/usr/bin/env bash
# ==============================================================================
# DevOps Manager: POSIX Bash Test Runner
# Invariant: [INV-002] Automated Test Harness
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR"

SUITES_TOTAL=0
SUITES_PASSED=0
SUITES_FAILED=0
FAILED_SUITES=()

echo "=========================================================="
echo "   DevOps Manager: POSIX Test Suite Runner                "
echo "=========================================================="

# Collect test files (either from arguments or discovering test_*.sh)
TEST_FILES=()
if [ $# -gt 0 ]; then
    for arg in "$@"; do
        if [ -f "$arg" ]; then
            TEST_FILES+=("$arg")
        elif [ -f "${TEST_DIR}/${arg}" ]; then
            TEST_FILES+=("${TEST_DIR}/${arg}")
        fi
    done
else
    while IFS= read -r file; do
        # Exclude helper and runner itself
        base="$(basename "$file")"
        if [ "$base" != "test_runner.sh" ] && [ "$base" != "test_helper.sh" ]; then
            TEST_FILES+=("$file")
        fi
    done < <(find "$TEST_DIR" -maxdepth 1 -type f -name "test_*.sh" | sort)
fi

START_TIME="$(date +%s)"

for test_file in "${TEST_FILES[@]}"; do
    SUITES_TOTAL=$((SUITES_TOTAL + 1))
    test_name="$(basename "$test_file")"
    echo ""
    echo ">> Running suite: $test_name"
    
    if bash "$test_file"; then
        SUITES_PASSED=$((SUITES_PASSED + 1))
        echo ">> [PASS] $test_name"
    else
        SUITES_FAILED=$((SUITES_FAILED + 1))
        FAILED_SUITES+=("$test_name")
        echo ">> [FAIL] $test_name" >&2
    fi
done

END_TIME="$(date +%s)"
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================================="
echo "   Test Run Summary: $SUITES_PASSED/$SUITES_TOTAL Suites Passed (${DURATION}s)"
echo "=========================================================="

if [ "$SUITES_FAILED" -gt 0 ]; then
    echo "Failed suites:" >&2
    for failed in "${FAILED_SUITES[@]}"; do
        echo "  - $failed" >&2
    done
    exit 1
fi

echo "All test suites completed successfully!"
exit 0
