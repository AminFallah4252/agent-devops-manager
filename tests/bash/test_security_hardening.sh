#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: test_security_hardening.sh
# Invariants: [INV-004] Host Hardening | [NEG-002] Clean Daemons | [NEG-003] Zero Secrets
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/apply-security-hardening.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing apply-security-hardening.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: apply-security-hardening.sh" "Displays usage help text"

# Test 2: Missing config path
set +e
MISSING_OUTPUT="$("$TARGET_SCRIPT" --config "non_existent.json" 2>&1)"
MISSING_CODE=$?
set -e
assert_exit_code 1 "$MISSING_CODE" "Exits with code 1 on missing config"
assert_contains "$MISSING_OUTPUT" "Configuration file not found" "Displays missing config error"

# Test 3: Dry-run execution
DRY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run)"
assert_contains "$DRY_OUTPUT" "Dry-run mode active" "Prints dry-run active notice"
assert_contains "$DRY_OUTPUT" "[UFW] Default policy: deny incoming" "Simulates default deny policy"
assert_contains "$DRY_OUTPUT" "[UFW] Allow TCP 22 (SSH)" "Simulates SSH allow rule"
assert_contains "$DRY_OUTPUT" "[Fail2ban] Configure jail.local" "Simulates Fail2ban configuration"
assert_contains "$DRY_OUTPUT" "Security hardening policies validated in dry-run mode" "Confirms policies validated"

# Test 4: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "security-hardening"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"firewall": "ufw"' "Specifies ufw firewall in JSON"
assert_contains "$JSON_OUTPUT" '"dry_run": 1' "Reflects dry_run state in JSON"

# Test 5: Mock execution - successful application
setup_mock_bin
create_mock "ssh" 'echo "Rules updated"; exit 0'

MOCK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$MOCK_OUTPUT" "Security hardening applied successfully" "Reports hardening applied"
teardown_mock_bin

# Test 6: Invariant verification [NEG-003] (Zero Hardcoded Secrets)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_sec_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" >/dev/null 2>&1 || true
CAPTURED_CMD="$(cat "${MOCK_DIR}/captured_sec_cmd.txt" 2>/dev/null || echo "")"
assert_not_contains "$CAPTURED_CMD" "password=" "Upholds NEG-003: No hardcoded password parameter"
assert_not_contains "$CAPTURED_CMD" "token=" "Upholds NEG-003: No hardcoded token parameter"
assert_contains "$CAPTURED_CMD" "ufw allow 22/tcp" "Configures SSH port in firewall command"
teardown_mock_bin

print_summary "apply-security-hardening.sh"
