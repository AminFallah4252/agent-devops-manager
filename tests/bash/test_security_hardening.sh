#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: test_security_hardening.sh
# Invariants: [INV-004] Host Hardening | [NEG-002] Clean Daemons | [NEG-003] Zero Secrets | [NEG-004] Zero Breaking Changes
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/apply-security-hardening.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing apply-security-hardening.sh ==="

# Test 1: Help command (--help and -h)
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: apply-security-hardening.sh" "Displays usage help text (--help)"
HELP_SHORT_OUTPUT="$("$TARGET_SCRIPT" -h)"
assert_contains "$HELP_SHORT_OUTPUT" "Usage: apply-security-hardening.sh" "Displays usage help text (-h)"

# Test 2: Missing config path
set +e
MISSING_OUTPUT="$("$TARGET_SCRIPT" --config "non_existent.json" 2>&1)"
MISSING_CODE=$?
set -e
assert_exit_code 1 "$MISSING_CODE" "Exits with code 1 on missing config"
assert_contains "$MISSING_OUTPUT" "Configuration file not found" "Displays missing config error"

# Test 3: Unknown profile validation
set +e
MISSING_PROF_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "unknown-profile" 2>&1)"
MISSING_PROF_CODE=$?
set -e
assert_exit_code 1 "$MISSING_PROF_CODE" "Exits with code 1 on unknown profile"
assert_contains "$MISSING_PROF_OUTPUT" "Profile 'unknown-profile' not found" "Displays unknown profile error"

# Test 4: Unknown argument handling
set +e
UNKNOWN_ARG_OUTPUT="$("$TARGET_SCRIPT" --invalid-flag 2>&1)"
UNKNOWN_ARG_CODE=$?
set -e
assert_exit_code 1 "$UNKNOWN_ARG_CODE" "Exits with code 1 on unknown argument"
assert_contains "$UNKNOWN_ARG_OUTPUT" "Error: Unknown argument" "Displays unknown argument error"

# Test 5: Dry-run execution with dynamic profile SSH port
DRY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run)"
assert_contains "$DRY_OUTPUT" "Dry-run mode active" "Prints dry-run active notice"
assert_contains "$DRY_OUTPUT" "[UFW] Default policy: deny incoming" "Simulates default deny policy"
assert_contains "$DRY_OUTPUT" "[UFW] Allow TCP 2222 (SSH)" "Simulates dynamic SSH allow rule from profile"
assert_contains "$DRY_OUTPUT" "[UFW] Allow TCP 80 (HTTP)" "Simulates HTTP allow rule"
assert_contains "$DRY_OUTPUT" "[UFW] Allow TCP 443 (HTTPS)" "Simulates HTTPS allow rule"
assert_contains "$DRY_OUTPUT" "[UFW] Allow in on docker0" "Simulates Docker bridge interface allow rule"
assert_contains "$DRY_OUTPUT" "[Fail2ban] Configure jail.local" "Simulates Fail2ban configuration"
assert_contains "$DRY_OUTPUT" "[sshd]" "Includes sshd jail in Fail2ban config"
assert_contains "$DRY_OUTPUT" "maxretry = 5" "Configures maxretry=5 in sshd jail"
assert_contains "$DRY_OUTPUT" "bantime = 1h" "Configures bantime=1h in sshd jail"
assert_contains "$DRY_OUTPUT" "findtime = 10m" "Configures findtime=10m in sshd jail"
assert_contains "$DRY_OUTPUT" "[nginx-req-limit]" "Includes nginx-req-limit jail in Fail2ban config"
assert_contains "$DRY_OUTPUT" "50unattended-upgrades" "Simulates 50unattended-upgrades configuration"
assert_contains "$DRY_OUTPUT" "20auto-upgrades" "Simulates 20auto-upgrades configuration"
assert_contains "$DRY_OUTPUT" "Security hardening policies validated in dry-run mode" "Confirms policies validated"

# Test 6: Short dry-run flag (-d)
DRY_SHORT_OUTPUT="$("$TARGET_SCRIPT" -c "$FIXTURE_CONFIG" -p "mock-profile" -d)"
assert_contains "$DRY_SHORT_OUTPUT" "Dry-run mode active" "Supports short -d flag"

# Test 7: Test-only mode (--test-only and -t)
TEST_ONLY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --test-only)"
assert_contains "$TEST_ONLY_OUTPUT" "Test-only mode active" "Supports --test-only flag"
assert_contains "$TEST_ONLY_OUTPUT" "Security hardening policies validated in test-only mode" "Confirms test-only validation"

TEST_ONLY_SHORT_OUTPUT="$("$TARGET_SCRIPT" -c "$FIXTURE_CONFIG" -p "mock-profile" -t)"
assert_contains "$TEST_ONLY_SHORT_OUTPUT" "Test-only mode active" "Supports short -t flag"

# Test 8: JSON output flag (--json and -j)
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "security-hardening"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"firewall": "ufw"' "Specifies ufw firewall in JSON"
assert_contains "$JSON_OUTPUT" '"dry_run": 1' "Reflects dry_run state in JSON"
assert_contains "$JSON_OUTPUT" '"ssh_port": 2222' "Outputs profile SSH port in JSON"
assert_contains "$JSON_OUTPUT" '"services": [' "Includes services list in JSON"

JSON_SHORT_OUTPUT="$("$TARGET_SCRIPT" -c "$FIXTURE_CONFIG" -p "mock-profile" -d -j)"
assert_contains "$JSON_SHORT_OUTPUT" '"action": "security-hardening"' "Supports short -j flag"

# Test 9: Mock execution - successful application with preflight check
setup_mock_bin
create_mock "ssh" 'echo "Rules updated"; exit 0'

MOCK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$MOCK_OUTPUT" "Verifying active SSH connection on port 2222 before committing firewall rules" "Runs pre-flight lockout check"
assert_contains "$MOCK_OUTPUT" "Security hardening applied successfully" "Reports hardening applied"
teardown_mock_bin

# Test 10: Invariant verification [NEG-003] (Zero Hardcoded Secrets) & Dynamic Port Injection
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_sec_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" >/dev/null 2>&1 || true
CAPTURED_CMD="$(cat "${MOCK_DIR}/captured_sec_cmd.txt" 2>/dev/null || echo "")"
assert_not_contains "$CAPTURED_CMD" "password=" "Upholds NEG-003: No hardcoded password parameter"
assert_not_contains "$CAPTURED_CMD" "token=" "Upholds NEG-003: No hardcoded token parameter"
assert_contains "$CAPTURED_CMD" "ufw allow 2222/tcp" "Configures dynamic SSH port in firewall command"
assert_contains "$CAPTURED_CMD" "ufw default deny incoming" "Configures default deny incoming"
assert_contains "$CAPTURED_CMD" "ufw allow 80/tcp" "Configures HTTP port in firewall command"
assert_contains "$CAPTURED_CMD" "ufw allow 443/tcp" "Configures HTTPS port in firewall command"
assert_contains "$CAPTURED_CMD" "ufw allow in on docker0" "Configures Docker bridge interface in firewall command"
assert_contains "$CAPTURED_CMD" "jail.local" "Deploys Fail2ban jail configuration"
assert_contains "$CAPTURED_CMD" "50unattended-upgrades" "Deploys 50unattended-upgrades configuration"
assert_contains "$CAPTURED_CMD" "20auto-upgrades" "Deploys 20auto-upgrades configuration"
teardown_mock_bin

# Test 11: Invariant [NEG-001] (Zero Destructive Pruning)
SCRIPT_CONTENT="$(cat "$TARGET_SCRIPT")"
assert_not_contains "$SCRIPT_CONTENT" "prune -a" "Upholds NEG-001: Never calls system prune -a"
assert_not_contains "$SCRIPT_CONTENT" "volume rm" "Upholds NEG-001: Never deletes persistent volumes"

# Test 12: Invariant [NEG-002] (No Custom Daemons)
assert_not_contains "$SCRIPT_CONTENT" "nohup" "Upholds NEG-002: No bare-metal background nohup daemons"
assert_not_contains "$SCRIPT_CONTENT" "python main.py" "Upholds NEG-002: No unmanaged Python daemons"

print_summary "apply-security-hardening.sh"
