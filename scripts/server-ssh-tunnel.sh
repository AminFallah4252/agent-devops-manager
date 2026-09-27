#!/usr/bin/env bash
# ==============================================================================
# DevOps Manager: Admin UI SSH Port-Forwarding Tunnel (POSIX/Bash)
# Invariants: [INV-001] Dual-Engine Parity | [NEG-002] Clean Daemons
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/../config.json"
PROFILE_NAME=""
CHECK_ONLY=0
DRY_RUN=0
OUTPUT_JSON=0

show_help() {
    cat << 'EOF'
Usage: server-ssh-tunnel.sh [OPTIONS]

Manages SSH port-forwarding tunnels for accessing private server administrative UIs:
  - 8008  -> Dockhand (Container Manager UI)
  - 3000  -> Grafana (Monitoring Dashboards)
  - 19090 -> Prometheus (Scraper / Metrics Engine)

Options:
  -p, --profile <name>      Target configuration profile name
  -c, --config <path>       Path to config.json (default: ../config.json)
  --check-only, -t, --test-only
                            Inspect whether the tunnel is active without starting it
  -d, --dry-run             Simulate tunnel operations without launching processes
  -j, --json                Output status in structured JSON
  -h, --help                Show this help message
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
        --check-only|-t|--test-only)
            CHECK_ONLY=1
            shift
            ;;
        -d|--dry-run)
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

PYTHON_CMD=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
        PYTHON_CMD="$cand"
        break
    fi
done

if [ -n "$PYTHON_CMD" ]; then
    PARSED_CONFIG="$("$PYTHON_CMD" - "$CONFIG_PATH" "$PROFILE_NAME" << 'EOF'
import json, sys

config_path = sys.argv[1]
req_profile = sys.argv[2]

try:
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception as e:
    sys.stderr.write(f"Error reading configuration: {e}\n")
    sys.exit(1)

prof_name = req_profile if req_profile else cfg.get("active_profile", "production")
profiles = cfg.get("profiles", {})

if prof_name not in profiles:
    sys.stderr.write(f"Error: Profile '{prof_name}' not found in {config_path}\n")
    sys.exit(2)

p = profiles[prof_name]
obs = p.get("observability", {})
tunnel_alias = obs.get("tunnel_alias", "hephaest-tunnel")

print(f"PROFILE_NAME='{prof_name}'")
print(f"TUNNEL_ALIAS='{tunnel_alias}'")
EOF
)" || {
        exit_code=$?
        echo "Error: Profile '$PROFILE_NAME' not found in $CONFIG_PATH" >&2
        exit $exit_code
    }
    eval "$PARSED_CONFIG"
else
    if [ -z "$PROFILE_NAME" ]; then
        if command -v jq >/dev/null 2>&1; then
            PROFILE_NAME="$(jq -r '.active_profile // empty' "$CONFIG_PATH")"
        fi
    fi
    [ -z "$PROFILE_NAME" ] && PROFILE_NAME="production"
    TUNNEL_ALIAS="mock-tunnel"
fi

is_port_bound() {
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":8008 "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":8008 " || netstat -an 2>/dev/null | grep -qE "(\.8008\b|:8008\b).*LISTEN"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i :8008 -sTCP:LISTEN >/dev/null 2>&1
    elif command -v nc >/dev/null 2>&1; then
        nc -z 127.0.0.1 8008 >/dev/null 2>&1
    else
        return 1
    fi
}

if [ "$OUTPUT_JSON" -eq 1 ]; then
    IS_ACTIVE=false
    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$CHECK_ONLY" -eq 0 ]; then
            IS_ACTIVE=true
        fi
    elif is_port_bound; then
        IS_ACTIVE=true
    fi
    cat << EOF
{
  "action": "ssh-tunnel",
  "tunnel_alias": "$TUNNEL_ALIAS",
  "port_8008_active": $IS_ACTIVE,
  "check_only": $CHECK_ONLY,
  "dry_run": $DRY_RUN
}
EOF
    exit 0
fi

echo "=========================================================="
echo "   DevOps Manager: Admin UI SSH Port-Forwarding Tunnel    "
echo "   Profile: ${PROFILE_NAME:-default} | Alias: ${TUNNEL_ALIAS}"
echo "=========================================================="

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[INFO] Dry-run mode active. Simulating port check..."
    if [ "$CHECK_ONLY" -eq 1 ]; then
        echo "[INFO] Tunnel is NOT active. Port 8008 is not bound (simulated)."
        exit 0
    fi
    echo "[OK] Tunnel command simulated: ssh -N -f ${TUNNEL_ALIAS}"
    echo "     - Dockhand UI:   http://localhost:8008"
    echo "     - Grafana:       http://localhost:3000"
    echo "     - Prometheus:    http://localhost:19090"
    exit 0
fi

if is_port_bound; then
    echo "[OK] Tunnel appears to be ACTIVE. Port 8008 is currently bound."
    echo "     - Dockhand UI:   http://localhost:8008"
    echo "     - Grafana:       http://localhost:3000"
    echo "     - Prometheus:    http://localhost:19090"
    exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "[INFO] Tunnel is NOT active. Port 8008 is not bound."
    exit 0
fi

echo "[*] Starting background SSH tunnel via alias '$TUNNEL_ALIAS'..."
if ssh -N -f "$TUNNEL_ALIAS"; then
    echo "[OK] Tunnel successfully established!"
    echo "     - Dockhand UI:   http://localhost:8008"
    echo "     - Grafana:       http://localhost:3000"
    echo "     - Prometheus:    http://localhost:19090"
else
    echo "[-] Failed to launch tunnel" >&2
    exit 1
fi
exit 0
