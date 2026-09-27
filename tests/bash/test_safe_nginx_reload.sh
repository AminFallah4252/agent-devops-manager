#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: safe-nginx-reload.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/safe-nginx-reload.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing safe-nginx-reload.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: safe-nginx-reload.sh" "Displays usage help text"

# Test 2: Missing config path
set +e
MISSING_OUTPUT="$("$TARGET_SCRIPT" --config "non_existent.json" 2>&1)"
MISSING_CODE=$?
set -e
assert_exit_code 1 "$MISSING_CODE" "Exits with code 1 on missing config"
assert_contains "$MISSING_OUTPUT" "Configuration file not found" "Displays missing config error"

# Test 3: Dry-run with test-only mode
DRY_TEST_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --test-only)"
assert_contains "$DRY_TEST_OUTPUT" "Dry-run mode active" "Dry-run mode active is printed"
assert_contains "$DRY_TEST_OUTPUT" "Test-only mode requested. Skipping reload." "Skips reload in test-only mode"

# Test 4: Dry-run full reload
DRY_RELOAD_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run)"
assert_contains "$DRY_RELOAD_OUTPUT" "Nginx successfully reloaded" "Simulates successful reload"

# Test 5: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "nginx-reload"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"status": "syntax_ok"' "Outputs JSON syntax_ok status"

# Test 6: Mock execution - successful syntax and reload
setup_mock_bin
create_mock "ssh" 'echo "nginx: syntax is ok"; exit 0'
MOCK_PASS_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$MOCK_PASS_OUTPUT" "Nginx successfully reloaded with zero downtime!" "Mock SSH succeeds with reload"
teardown_mock_bin

# Test 7: Mock execution - failing syntax check aborts reload
setup_mock_bin
create_mock "ssh" 'echo "nginx: syntax error in /etc/nginx/nginx.conf" >&2; exit 1'
set +e
MOCK_FAIL_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" 2>&1)"
MOCK_FAIL_CODE=$?
set -e
assert_exit_code 1 "$MOCK_FAIL_CODE" "Syntax check failure returns exit code 1"
assert_contains "$MOCK_FAIL_OUTPUT" "Reload ABORTED to protect active web traffic" "Aborts reload when syntax is invalid"
teardown_mock_bin

print_summary "safe-nginx-reload.sh"
