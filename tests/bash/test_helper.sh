#!/usr/bin/env bash
# ==============================================================================
# POSIX Test Helper and Assertion Framework for DevOps Manager
# ==============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
MOCK_DIR=""

setup_mock_bin() {
    MOCK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'mockbin')"
    ORIGINAL_PATH="$PATH"
    export PATH="${MOCK_DIR}:${PATH}"
}

teardown_mock_bin() {
    if [ -n "$MOCK_DIR" ] && [ -d "$MOCK_DIR" ]; then
        rm -rf "$MOCK_DIR"
    fi
    if [ -n "${ORIGINAL_PATH:-}" ]; then
        export PATH="$ORIGINAL_PATH"
    fi
}

create_mock() {
    local cmd_name="$1"
    local mock_script="$2"
    local target_file="${MOCK_DIR}/${cmd_name}"
    cat << EOF > "$target_file"
#!/usr/bin/env bash
$mock_script
EOF
    chmod +x "$target_file"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Assertion}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "  [FAIL] $desc" >&2
        echo "         Expected: '$expected'" >&2
        echo "         Got:      '$actual'" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-Assertion}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [PASS] $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "  [FAIL] $desc (substring '$needle' not found in output)" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-Assertion}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [FAIL] $desc (unwanted substring '$needle' was found)" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        echo "  [PASS] $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Exit code assertion}"
    assert_equals "$expected" "$actual" "$desc"
}

print_summary() {
    local suite_name="${1:-Test Suite}"
    echo "----------------------------------------------------------"
    echo "Suite: $suite_name | Total: $TESTS_RUN | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}
