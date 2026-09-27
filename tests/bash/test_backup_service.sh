#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: backup-service.sh
# Invariants: [INV-003] Backup & Disaster Recovery | [NEG-001] Zero Destructive Pruning
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/backup-service.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing backup-service.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: backup-service.sh" "Displays usage help text"

# Test 2: Missing config path
set +e
MISSING_OUTPUT="$("$TARGET_SCRIPT" --config "non_existent.json" 2>&1)"
MISSING_CODE=$?
set -e
assert_exit_code 1 "$MISSING_CODE" "Exits with code 1 on missing config"
assert_contains "$MISSING_OUTPUT" "Configuration file not found" "Displays missing config error"

# Test 3: Dry-run execution
DRY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --service "nginx-proxy" --dry-run)"
assert_contains "$DRY_OUTPUT" "Dry-run / Test-only mode enabled" "Prints dry-run active notice"
assert_contains "$DRY_OUTPUT" "Ephemeral Strategy: alpine tar czf" "Specifies ephemeral Alpine strategy"
assert_contains "$DRY_OUTPUT" "Retention Sweep: find" "Specifies retention sweep command"

# Test 4: Test-only alias flag
TEST_ONLY_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --test-only)"
assert_contains "$TEST_ONLY_OUTPUT" "Dry-run / Test-only mode enabled" "Supports --test-only flag"

# Test 5: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --service "postgres" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "backup"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"service": "postgres"' "Outputs service name in JSON"
assert_contains "$JSON_OUTPUT" '"dry_run": 1' "Reflects dry_run state in JSON"

# Test 6: Mock execution - successful backup
setup_mock_bin
create_mock "ssh" 'echo "tar: archive created"; exit 0'

MOCK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --service "grafana")"
assert_contains "$MOCK_OUTPUT" "Backup completed successfully without volume interference" "Mock SSH backup succeeds"
teardown_mock_bin

# Test 7: Invariant verification [NEG-001] (Zero Destructive Pruning)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_backup_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --service "webapp" >/dev/null 2>&1 || true
CAPTURED_CMD="$(cat "${MOCK_DIR}/captured_backup_cmd.txt" 2>/dev/null || echo "")"
assert_not_contains "$CAPTURED_CMD" "system prune" "Upholds NEG-001: Never calls system prune"
assert_not_contains "$CAPTURED_CMD" "volume rm" "Upholds NEG-001: Never removes persistent volumes"
assert_contains "$CAPTURED_CMD" "docker run --rm" "Uses ephemeral container"
assert_contains "$CAPTURED_CMD" "alpine tar czf" "Compresses volume data with tar"
teardown_mock_bin

print_summary "backup-service.sh"
