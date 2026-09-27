#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: server-ssh-tunnel.sh
# Invariants: [INV-001] Dual-Engine Parity | [NEG-002] Clean Daemons
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/server-ssh-tunnel.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing server-ssh-tunnel.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: server-ssh-tunnel.sh" "Displays usage help text"

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
assert_contains "$DRY_OUTPUT" "Tunnel command simulated: ssh -N -f mock-tunnel" "Simulates SSH tunnel command"
assert_contains "$DRY_OUTPUT" "http://localhost:8008" "Displays Dockhand port URL"

# Test 4: Dry-run check-only mode
DRY_CHECK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --check-only)"
assert_contains "$DRY_CHECK_OUTPUT" "Tunnel is NOT active. Port 8008 is not bound" "Confirms check-only behavior"

# Test 5: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "ssh-tunnel"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"tunnel_alias": "mock-tunnel"' "Outputs correct tunnel alias in JSON"
assert_contains "$JSON_OUTPUT" '"port_8008_active": true' "Reflects port state in JSON"

# Test 6: Mock execution - active port detected
setup_mock_bin
create_mock "ss" 'echo "LISTEN 0 128 127.0.0.1:8008 0.0.0.0:*"; exit 0'

ACTIVE_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$ACTIVE_OUTPUT" "Tunnel appears to be ACTIVE. Port 8008 is currently bound." "Detects active port 8008"
teardown_mock_bin

# Test 7: Mock execution - launching tunnel when inactive
setup_mock_bin
create_mock "ss" 'exit 1'
create_mock "netstat" 'exit 1'
create_mock "nc" 'exit 1'
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/tunnel_launched.txt\"; exit 0"

LAUNCH_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$LAUNCH_OUTPUT" "Starting background SSH tunnel" "Initiates tunnel startup"
assert_contains "$LAUNCH_OUTPUT" "Tunnel successfully established!" "Reports tunnel established"

LAUNCH_RECORD="$(cat "${MOCK_DIR}/tunnel_launched.txt" 2>/dev/null || echo "")"
assert_contains "$LAUNCH_RECORD" "-N -f mock-tunnel" "Passes -N -f mock-tunnel arguments"
teardown_mock_bin

# Test 8: Missing profile validation
set +e
MISSING_PROF_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "unknown-profile" 2>&1)"
MISSING_PROF_CODE=$?
set -e
assert_exit_code 1 "$MISSING_PROF_CODE" "Exits with code 1 on unknown profile"
assert_contains "$MISSING_PROF_OUTPUT" "Profile 'unknown-profile' not found" "Displays unknown profile error"

# Test 9: Test-only flag behaves like check-only
DRY_TEST_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run -t)"
assert_contains "$DRY_TEST_OUTPUT" "Tunnel is NOT active. Port 8008 is not bound (simulated)." "Supports -t/--test-only flag"

print_summary "server-ssh-tunnel.sh"
