#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: docker-cleanup.sh
# Invariant: [NEG-001] Zero Destructive Pruning
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TARGET_SCRIPT="${SCRIPT_DIR}/../../scripts/docker-cleanup.sh"
FIXTURE_CONFIG="${SCRIPT_DIR}/../fixtures/test-config.json"

echo "=== Testing docker-cleanup.sh ==="

# Test 1: Help command
HELP_OUTPUT="$("$TARGET_SCRIPT" --help)"
assert_contains "$HELP_OUTPUT" "Usage: docker-cleanup.sh" "Displays usage help text"

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
assert_contains "$DRY_OUTPUT" "Persistent Volumes Intact" "Confirms persistent volumes intact"

# Test 4: JSON output flag
JSON_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --dry-run --json)"
assert_contains "$JSON_OUTPUT" '"action": "docker-cleanup"' "Outputs valid JSON action"
assert_contains "$JSON_OUTPUT" '"volumes_preserved": true' "Confirms volumes_preserved in JSON"

# Test 5: Mock execution
setup_mock_bin
create_mock "ssh" 'cat << "EOF"
===PRE_DISK===
/dev/sda1        40G   30G   10G  75% /
===PRUNING===
Deleted Images:
untagged: image:latest
===POST_DISK===
/dev/sda1        40G   27G   13G  68% /
EOF
exit 0'

MOCK_OUTPUT="$("$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile")"
assert_contains "$MOCK_OUTPUT" "Hygiene Protocol Complete. Persistent Volumes Intact." "Reports hygiene complete"
teardown_mock_bin

# Test 6: Invariant verification [NEG-001] (Zero Destructive Pruning)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_args.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" >/dev/null 2>&1 || true
CAPTURED_ARGS="$(cat "${MOCK_DIR}/captured_args.txt" 2>/dev/null || echo "")"
assert_not_contains "$CAPTURED_ARGS" "system prune -a" "Upholds NEG-001: Never calls system prune -a"
assert_not_contains "$CAPTURED_ARGS" "--volumes" "Upholds NEG-001: Never deletes volumes"
assert_contains "$CAPTURED_ARGS" "image prune -f" "Uses safe image prune"
assert_contains "$CAPTURED_ARGS" "builder prune -f" "Uses safe builder prune"
teardown_mock_bin

print_summary "docker-cleanup.sh"
