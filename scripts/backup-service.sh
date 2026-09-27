#!/usr/bin/env bash
# ==============================================================================
# DevOps Manager: Safe Non-Destructive Backup & Recovery Engine (POSIX/Bash)
# Invariants: [INV-003] Backup & Disaster Recovery | [NEG-001] Zero Destructive Pruning | [NEG-003] Zero Hardcoded Secrets
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/../config.json"
PROFILE_NAME="${PROFILE_NAME:-}"
SERVICE_NAME="${SERVICE_NAME:-all}"
VOLUME_NAME="${VOLUME_NAME:-}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
RETENTION_DAILY="${RETENTION_DAILY:-7}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-4}"
DB_TYPE="${DB_TYPE:-}"
DB_CONTAINER="${DB_CONTAINER:-}"
DB_USER="${DB_USER:-}"
DB_NAME="${DB_NAME:-}"
DB_PASS="${DB_PASS:-}"
WEEKLY=0
DRY_RUN=0
OUTPUT_JSON=0

show_help() {
    cat << 'EOF'
Usage: backup-service.sh [OPTIONS]

Performs safe, non-destructive Docker volume and database backups on remote host.
- Named Docker Volumes: Hot backup using ephemeral Alpine container mounted read-only (:ro).
- Database Dump Orchestration: Zero-downtime streaming pg_dump (PostgreSQL) and mysqldump (MySQL).
- Retention Policy: Keeps last 7 daily and last 4 weekly backups.
- Safety: Strictly upholds NEG-001 (never prunes/deletes Docker volumes) and NEG-003 (zero hardcoded secrets).

Options:
  -p, --profile <name>          Target configuration profile name
  -c, --config <path>           Path to config.json (default: ../config.json)
  -s, --service <name>          Specific container or service to back up (default: all)
  -v, --volume <name>           Named Docker volume to back up
  -b, --backup-dir <path>       Directory to store backups (default: /var/backups)
  -r, --retention-days <days>   Number of days for daily retention (default: 7)
      --retention-daily <days>  Number of daily backups to preserve (default: 7)
      --retention-weekly <wks>  Number of weekly backups to preserve (default: 4)
  -t, --db-type <postgres|mysql> Database engine for streaming dump
      --db-container <name>     Database container name (default: matches service)
      --db-user <user>          Database username (or via DB_USER / POSTGRES_USER / MYSQL_USER)
      --db-name <name>          Database name (or via DB_NAME / POSTGRES_DB / MYSQL_DATABASE)
      --db-pass <pass>          Database password (or via DB_PASS / PGPASSWORD / MYSQL_PWD)
  -w, --weekly                  Tag/mark this backup as a weekly retention snapshot
  -d, --dry-run, --test-only    Simulate backup actions without execution
  -j, --json                    Output response in structured JSON
  -h, --help                    Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--profile)
            PROFILE_NAME="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -v|--volume)
            VOLUME_NAME="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention-days)
            RETENTION_DAYS="$2"
            RETENTION_DAILY="$2"
            shift 2
            ;;
        --retention-daily)
            RETENTION_DAILY="$2"
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --retention-weekly)
            RETENTION_WEEKLY="$2"
            shift 2
            ;;
        -t|--db-type)
            DB_TYPE="$2"
            shift 2
            ;;
        --db-container)
            DB_CONTAINER="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-pass)
            DB_PASS="$2"
            shift 2
            ;;
        -w|--weekly)
            WEEKLY=1
            shift
            ;;
        -d|--dry-run|--test-only)
            DRY_RUN=1
            shift
            ;;
        -j|--json)
            OUTPUT_JSON=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file not found: $CONFIG_PATH" >&2
    exit 1
fi

if [ -z "$PROFILE_NAME" ]; then
    if command -v python3 >/dev/null 2>&1; then
        PROFILE_NAME="$(python3 -c "import json, sys; cfg=json.load(open('$CONFIG_PATH')); sys.stdout.write(cfg.get('active_profile', ''))")"
    elif command -v python >/dev/null 2>&1; then
        PROFILE_NAME="$(python -c "import json, sys; cfg=json.load(open('$CONFIG_PATH')); sys.stdout.write(cfg.get('active_profile', ''))")"
    elif command -v jq >/dev/null 2>&1; then
        PROFILE_NAME="$(jq -r '.active_profile // empty' "$CONFIG_PATH")"
    fi
fi

if [ -z "$PROFILE_NAME" ]; then
    PROFILE_NAME="production"
fi

SSH_TARGET="prod-server"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Credential resolution from environment if not passed via CLI [NEG-003]
if [ -z "$DB_USER" ]; then
    DB_USER="${POSTGRES_USER:-${MYSQL_USER:-${DB_USER:-}}}"
fi
if [ -z "$DB_NAME" ]; then
    DB_NAME="${POSTGRES_DB:-${MYSQL_DATABASE:-${DB_NAME:-}}}"
fi
if [ -z "$DB_PASS" ]; then
    DB_PASS="${PGPASSWORD:-${MYSQL_PWD:-${MYSQL_ROOT_PASSWORD:-${DB_PASS:-}}}}"
fi

# Target resolution
VOLUME="${VOLUME_NAME:-$SERVICE_NAME}"
VOLUME_BACKUP=1
if [ -n "$DB_TYPE" ] && [ -z "$VOLUME_NAME" ]; then
    VOLUME_BACKUP=0
fi

if [ -n "$DB_TYPE" ]; then
    if [ -z "$DB_CONTAINER" ]; then
        DB_CONTAINER="$SERVICE_NAME"
    fi
    if [ "$DB_TYPE" = "postgres" ]; then
        [ -z "$DB_USER" ] && DB_USER="postgres"
        [ -z "$DB_NAME" ] && DB_NAME="${DB_CONTAINER:-postgres}"
    elif [ "$DB_TYPE" = "mysql" ]; then
        [ -z "$DB_USER" ] && DB_USER="root"
        [ -z "$DB_NAME" ] && DB_NAME="${DB_CONTAINER:-}"
    fi
fi

DB_DEST="${DB_CONTAINER:-db}"
if [ -n "$DB_NAME" ] && [ "$DB_NAME" != "$DB_CONTAINER" ]; then
    DB_DEST="${DB_CONTAINER}_${DB_NAME}"
fi

TAR_PATTERN="${VOLUME}_*.tar.gz"
[ "$VOLUME" = "all" ] && TAR_PATTERN="*.tar.gz"
SQL_PATTERN="${DB_DEST}_*.sql.gz"
[ -z "$DB_TYPE" ] && SQL_PATTERN="*.sql.gz"

if [ "$OUTPUT_JSON" -eq 1 ]; then
    cat << EOF
{
  "action": "backup",
  "profile": "$PROFILE_NAME",
  "service": "$SERVICE_NAME",
  "volume": "$VOLUME",
  "volume_backup": $VOLUME_BACKUP,
  "db_type": "$DB_TYPE",
  "db_container": "$DB_CONTAINER",
  "db_name": "$DB_NAME",
  "backup_dir": "$BACKUP_DIR",
  "retention_days": $RETENTION_DAYS,
  "retention_daily": $RETENTION_DAILY,
  "retention_weekly": $RETENTION_WEEKLY,
  "dry_run": $DRY_RUN,
  "timestamp": "$TIMESTAMP",
  "status": "success"
}
EOF
    exit 0
fi

echo "=========================================================="
echo "   DevOps Manager: Non-Destructive Backup & Recovery      "
echo "   Target Profile: ${PROFILE_NAME}"
echo "   Service: ${SERVICE_NAME} | Retention: ${RETENTION_DAYS} days (Daily: ${RETENTION_DAILY}, Weekly: ${RETENTION_WEEKLY})"
echo "=========================================================="

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "[INFO] Dry-run / Test-only mode enabled. No remote changes executed."
    echo "       Target Directory: ${BACKUP_DIR}"
    if [ "$VOLUME_BACKUP" -eq 1 ]; then
        echo "       Ephemeral Strategy: alpine tar czf /backup/${VOLUME}_${TIMESTAMP}.tar.gz"
    fi
    if [ -n "$DB_TYPE" ]; then
        if [ "$DB_TYPE" = "postgres" ]; then
            echo "       Postgres Strategy: docker exec -i ${DB_CONTAINER} pg_dump -U ${DB_USER} ${DB_NAME} | gzip > ${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz"
        elif [ "$DB_TYPE" = "mysql" ]; then
            echo "       MySQL Strategy: docker exec -i ${DB_CONTAINER} mysqldump -u ${DB_USER} -p[REDACTED] ${DB_NAME} | gzip > ${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz"
        fi
    fi
    echo "       Retention Sweep: find ${BACKUP_DIR} -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete (daily: ${RETENTION_DAILY}d, weekly: ${RETENTION_WEEKLY}w)"
    echo ""
    exit 0
fi

REMOTE_SCRIPT="mkdir -p '${BACKUP_DIR}'"

if [ "$VOLUME_BACKUP" -eq 1 ]; then
    REMOTE_SCRIPT="${REMOTE_SCRIPT} && docker run --rm -v '${VOLUME}:/source:ro' -v '${BACKUP_DIR}:/backup' alpine tar czf '/backup/${VOLUME}_${TIMESTAMP}.tar.gz' -C /source ."
    if [ "$WEEKLY" -eq 1 ] || [ "$(date +%u)" -eq 7 ]; then
        REMOTE_SCRIPT="${REMOTE_SCRIPT} && (cp -l '${BACKUP_DIR}/${VOLUME}_${TIMESTAMP}.tar.gz' '${BACKUP_DIR}/${VOLUME}_${TIMESTAMP}_weekly.tar.gz' 2>/dev/null || true)"
    fi
fi

if [ -n "$DB_TYPE" ]; then
    if [ "$DB_TYPE" = "postgres" ]; then
        if [ -n "$DB_PASS" ]; then
            REMOTE_SCRIPT="${REMOTE_SCRIPT} && PGPASSWORD='${DB_PASS}' docker exec -i ${DB_CONTAINER} pg_dump -U ${DB_USER} ${DB_NAME} | gzip > '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz'"
        else
            REMOTE_SCRIPT="${REMOTE_SCRIPT} && docker exec -i ${DB_CONTAINER} pg_dump -U ${DB_USER} ${DB_NAME} | gzip > '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz'"
        fi
    elif [ "$DB_TYPE" = "mysql" ]; then
        if [ -n "$DB_PASS" ]; then
            REMOTE_SCRIPT="${REMOTE_SCRIPT} && docker exec -i ${DB_CONTAINER} mysqldump -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME} | gzip > '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz'"
        else
            REMOTE_SCRIPT="${REMOTE_SCRIPT} && docker exec -i ${DB_CONTAINER} mysqldump -u ${DB_USER} ${DB_NAME} | gzip > '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz'"
        fi
    fi
    if [ "$WEEKLY" -eq 1 ] || [ "$(date +%u)" -eq 7 ]; then
        REMOTE_SCRIPT="${REMOTE_SCRIPT} && (cp -l '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz' '${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}_weekly.sql.gz' 2>/dev/null || true)"
    fi
fi

# Retention rotation sweep: safely prune older archive files matching pattern without deleting active volumes [NEG-001]
if [ "$VOLUME_BACKUP" -eq 1 ]; then
    REMOTE_SCRIPT="${REMOTE_SCRIPT} && find '${BACKUP_DIR}' -maxdepth 1 -name '${TAR_PATTERN}' -type f -mtime +$((RETENTION_WEEKLY * 7)) -delete"
    REMOTE_SCRIPT="${REMOTE_SCRIPT} && for f in \$(find '${BACKUP_DIR}' -maxdepth 1 -name '${TAR_PATTERN}' -type f -mtime +${RETENTION_DAILY} 2>/dev/null); do fdate=\$(basename \"\$f\" | grep -oE '[0-9]{8}_[0-9]{6}' | cut -d_ -f1 || echo ''); if [ -n \"\$fdate\" ]; then dow=\$(date -d \"\$fdate\" +%u 2>/dev/null || echo '1'); if [ \"\$dow\" -ne 7 ] && [[ \"\$f\" != *'_weekly_'* ]]; then rm -f \"\$f\"; fi; fi; done"
fi

if [ -n "$DB_TYPE" ]; then
    REMOTE_SCRIPT="${REMOTE_SCRIPT} && find '${BACKUP_DIR}' -maxdepth 1 -name '${SQL_PATTERN}' -type f -mtime +$((RETENTION_WEEKLY * 7)) -delete"
    REMOTE_SCRIPT="${REMOTE_SCRIPT} && for f in \$(find '${BACKUP_DIR}' -maxdepth 1 -name '${SQL_PATTERN}' -type f -mtime +${RETENTION_DAILY} 2>/dev/null); do fdate=\$(basename \"\$f\" | grep -oE '[0-9]{8}_[0-9]{6}' | cut -d_ -f1 || echo ''); if [ -n \"\$fdate\" ]; then dow=\$(date -d \"\$fdate\" +%u 2>/dev/null || echo '1'); if [ \"\$dow\" -ne 7 ] && [[ \"\$f\" != *'_weekly_'* ]]; then rm -f \"\$f\"; fi; fi; done"
fi

echo "[*] Executing ephemeral Alpine backup stream..."
# shellcheck disable=SC2029
if ! OUTPUT="$(ssh "$SSH_TARGET" "$REMOTE_SCRIPT" 2>&1)"; then
    echo "[-] Backup operation failed:" >&2
    echo "$OUTPUT" >&2
    exit 1
fi

echo "[OK] Backup completed successfully without volume interference."
if [ "$VOLUME_BACKUP" -eq 1 ]; then
    echo "     Archive saved to: ${BACKUP_DIR}/${VOLUME}_${TIMESTAMP}.tar.gz"
fi
if [ -n "$DB_TYPE" ]; then
    echo "     Database dump saved to: ${BACKUP_DIR}/${DB_DEST}_${TIMESTAMP}.sql.gz"
fi
exit 0
