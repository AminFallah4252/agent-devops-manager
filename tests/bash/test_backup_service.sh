#!/usr/bin/env bash
# ==============================================================================
# Unit & Integration Tests: backup-service.sh
# Invariants: [INV-003] Backup & Disaster Recovery | [NEG-001] Zero Destructive Pruning | [NEG-003] Zero Hardcoded Secrets
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

# Test 8: [INV-003] Zero-downtime hot backup of named Docker volumes (:ro mount and ephemeral Alpine)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_vol_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --volume "app_data_vol" --backup-dir "/srv/backups" >/dev/null 2>&1 || true
VOL_CMD="$(cat "${MOCK_DIR}/captured_vol_cmd.txt" 2>/dev/null || echo "")"
assert_contains "$VOL_CMD" "-v 'app_data_vol:/source:ro'" "Mounts named Docker volume read-only (:ro)"
assert_contains "$VOL_CMD" "-v '/srv/backups:/backup'" "Mounts backup destination directory"
assert_contains "$VOL_CMD" "alpine tar czf '/backup/app_data_vol_" "Creates compressed tarball with timestamp"
assert_contains "$VOL_CMD" "-C /source ." "Archives from /source directory root"
teardown_mock_bin

# Test 9: [INV-003] Streaming PostgreSQL database dump orchestration
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_pg_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --db-type "postgres" --db-container "pg-server" --db-user "dbadmin" --db-name "appdb" >/dev/null 2>&1 || true
PG_CMD="$(cat "${MOCK_DIR}/captured_pg_cmd.txt" 2>/dev/null || echo "")"
assert_contains "$PG_CMD" "docker exec -i pg-server pg_dump -U dbadmin appdb | gzip >" "Streams pg_dump via docker exec to compressed gzip"
teardown_mock_bin

# Test 10: [INV-003] Streaming MySQL database dump orchestration
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_mysql_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --db-type "mysql" --db-container "mysql-db" --db-user "root" --db-name "ecommerce" --db-pass "s3cret!" >/dev/null 2>&1 || true
MYSQL_CMD="$(cat "${MOCK_DIR}/captured_mysql_cmd.txt" 2>/dev/null || echo "")"
assert_contains "$MYSQL_CMD" "docker exec -i mysql-db mysqldump -u root -p's3cret!' ecommerce | gzip >" "Streams mysqldump via docker exec to compressed gzip"
teardown_mock_bin

# Test 11: [INV-003] Retention Rotation Policy (Daily 7 & Weekly 4)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_retention_cmd.txt\"; exit 0"

"$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --service "analytics" --retention-daily 7 --retention-weekly 4 >/dev/null 2>&1 || true
RET_CMD="$(cat "${MOCK_DIR}/captured_retention_cmd.txt" 2>/dev/null || echo "")"
assert_contains "$RET_CMD" "-mtime +28 -delete" "Prunes archives older than 4 weekly retention limit (28 days)"
assert_contains "$RET_CMD" "-mtime +7" "Filters daily retention window (7 days)"
assert_contains "$RET_CMD" "analytics_*.tar.gz" "Scuffs only matching archive pattern without touching persistent volumes"
teardown_mock_bin

# Test 12: Invariant verification [NEG-003] (Zero Hardcoded Secrets)
setup_mock_bin
create_mock "ssh" "echo \"\$*\" > \"${MOCK_DIR}/captured_sec_cmd.txt\"; exit 0"

# Verify credentials can be passed dynamically via environment variables
DB_USER="envuser" DB_NAME="envdb" "$TARGET_SCRIPT" --config "$FIXTURE_CONFIG" --profile "mock-profile" --db-type "postgres" --db-container "env-pg" >/dev/null 2>&1 || true
SEC_CMD="$(cat "${MOCK_DIR}/captured_sec_cmd.txt" 2>/dev/null || echo "")"
assert_contains "$SEC_CMD" "docker exec -i env-pg pg_dump -U envuser envdb" "Resolves DB credentials dynamically from environment"

# Assert no hardcoded static passwords in script source code
SCRIPT_SRC="$(cat "$TARGET_SCRIPT")"
assert_not_contains "$SCRIPT_SRC" "s3cret" "No hardcoded secrets in backup script"
assert_not_contains "$SCRIPT_SRC" "password123" "No default hardcoded test passwords in script"
teardown_mock_bin

print_summary "backup-service.sh"
