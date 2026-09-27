#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: server-health-audit.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/server-health-audit.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing server-health-audit.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: server-health-audit.sh" "Displays usage help text"

# Test 2: Missing config path
set +e
MISSING_OUTPUT="$("$TARGET_SCRIPT" --config "non_existent.json" 2>&1)"
MISSING_CODE=$?
set -e
assert_exit_code 1 "$MISSING_CODE" "Exits with code 1 on missing config"
assert_contains "$MISSING_OUTPUT" "Configuration file not found" "Displays missing config error"

# Test 3: Dry-run execution
DRY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run)"
assert_contains "$DRY_OUTPUT" "System Uptime and Load (simulation)" "Displays simulated uptime"
assert_contains "$DRY_OUTPUT" "RAM headroom is healthy." "Displays RAM headroom status"
assert_contains "$DRY_OUTPUT" "Disk headroom is within safe operating parameters." "Displays disk status"
assert_contains "$DRY_OUTPUT" "nginx-proxy" "Lists simulated containers"
assert_contains "$DRY_OUTPUT" "Audit Complete: Ready for Operations" "Completes audit in dry-run mode"

# Test 4: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "health-audit"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"status": "healthy"' "Outputs JSON healthy status"
assert_contains "$JSON_OUTPUT" '"containers_active":' "Includes container metrics in JSON"

# Test 5: Mock execution - successful health audit
setup_mock_bin
create_mock "ssh" 'cat << "EOF"
===UPTIME===
 10:00:00 up 20 days, load average: 0.10, 0.08, 0.05
===MEMORY===
Mem: 8000000000 4000000000 2000000000 100000000 2000000000 3800000000
===DISK===
/dev/root 40000000 20000000 20000000 50% /
===DOCKER===
nginx-proxy:::Up 5 days:::80/tcp
EOF
exit 0'

MOCK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$MOCK_OUTPUT" "Audit Complete: Ready for Operations" "Mock SSH succeeds with complete audit"
teardown_mock_bin

# Test 6: Mock execution - SSH failure
setup_mock_bin
create_mock "ssh" 'echo "Connection timed out" >&2; exit 255'

set +e
MOCK_FAIL_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" 2>&1)"
MOCK_FAIL_CODE=$?
set -e
assert_exit_code 1 "$MOCK_FAIL_CODE" "Connection error returns exit code 1"
assert_contains "$MOCK_FAIL_OUTPUT" "Failed to connect or execute remote health audit" "Reports connection failure message"
teardown_mock_bin

# Test 7: Missing profile validation
set +e
MISSING_PROF_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "unknown-profile" 2>&1)"
MISSING_PROF_CODE=$?
set -e
assert_exit_code 1 "$MISSING_PROF_CODE" "Exits with code 1 on unknown profile"
assert_contains "$MISSING_PROF_OUTPUT" "Profile 'unknown-profile' not found" "Displays unknown profile error"

# Test 8: Test-only flag behaves like dry-run
TEST_ONLY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" -t)"
assert_contains "$TEST_ONLY_OUTPUT" "System Uptime and Load (simulation)" "Supports -t/--test-only flag"

# Test 9: RAM threshold alert
setup_mock_bin
create_mock "ssh" 'cat << "EOF"
===UPTIME===
 10:00:00 up 20 days, load average: 0.10, 0.08, 0.05
===MEMORY===
Mem: 8000000000 7500000000 500000000 100000000 500000000 300000000
===DISK===
/dev/root 40000000 20000000 20000000 50% /
===DOCKER===
NO_DOCKER
EOF
exit 0'
RAM_WARN_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$RAM_WARN_OUTPUT" "WARNING: RAM usage exceeds threshold" "Emits RAM threshold warning"
teardown_mock_bin

print_summary "server-health-audit.sh"
