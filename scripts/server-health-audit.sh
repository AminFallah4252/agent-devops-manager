#!/usr/bin/env bash
# ==============================================================================
# DevOps Manager: Remote Health and Triage Audit (POSIX/Bash)
# Invariants: [INV-001] Dual-Engine Parity | [INV-005] Threshold Checks
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/../config.json"
PROFILE_NAME=""
DRY_RUN=0
OUTPUT_JSON=0

show_help() {
    cat << 'EOF'
Usage: server-health-audit.sh [OPTIONS]

Runs a non-destructive multi-metric health audit on a managed remote server.
Inspects CPU load, RAM, swap, disk headroom, and running Docker containers.

Options:
  -p, --profile <name>      Target configuration profile name
  -c, --config <path>       Path to config.json (default: ../config.json)
  -d, --dry-run             Simulate health check against sample metrics
  -t, --test-only           Alias for dry-run (simulation mode)
  -j, --json                Output response in structured JSON
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
        -d|--dry-run|-t|--test-only)
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

# Locate Python interpreter for JSON and threshold computation
PYTHON_CMD=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
        PYTHON_CMD="$cand"
        break
    fi
done

if [ -n "$PYTHON_CMD" ]; then
    if ! PARSED_CONFIG="$("$PYTHON_CMD" - "$CONFIG_PATH" "$PROFILE_NAME" << 'EOF'
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
thresh = p.get("thresholds", {})

print(f"PROFILE_NAME='{prof_name}'")
print(f"TARGET_NAME='{p.get('name', prof_name)}'")
print(f"SSH_HOST='{p.get('host', '')}'")
print(f"SSH_USER='{p.get('user', '')}'")
print(f"SSH_PORT='{p.get('ssh_port', '')}'")
print(f"SSH_ALIAS='{p.get('ssh_alias', '')}'")
print(f"MAX_RAM_USAGE_PERCENT='{thresh.get('max_ram_usage_percent', 85.0)}'")
print(f"MIN_FREE_DISK_GB='{thresh.get('min_free_disk_gb', 3.0)}'")
EOF
)"; then
        exit 1
    fi
    eval "$PARSED_CONFIG"
else
    # Fallback when Python is unavailable
    if [ -z "$PROFILE_NAME" ]; then
        if command -v jq >/dev/null 2>&1; then
            PROFILE_NAME="$(jq -r '.active_profile // empty' "$CONFIG_PATH")"
        fi
    fi
    [ -z "$PROFILE_NAME" ] && PROFILE_NAME="production"
    TARGET_NAME="$PROFILE_NAME"
    SSH_HOST="127.0.0.1"
    SSH_USER="admin"
    SSH_PORT=""
    SSH_ALIAS=""
    MAX_RAM_USAGE_PERCENT="85.0"
    MIN_FREE_DISK_GB="3.0"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$OUTPUT_JSON" -eq 1 ]; then
        cat << EOF
{
  "action": "health-audit",
  "profile": "$PROFILE_NAME",
  "dry_run": true,
  "status": "healthy",
  "metrics": {
    "uptime_days": 45,
    "ram_used_percent": 60.0,
    "disk_free_gb": 18.0,
    "containers_active": 2
  }
}
EOF
        exit 0
    fi

    echo "=========================================================="
    echo "   DevOps Manager: Remote Health and Triage Audit         "
    echo "   Target Profile: ${PROFILE_NAME}"
    echo "=========================================================="
    echo ""
    echo "[+] System Uptime and Load (simulation):"
    echo "    12:00:00 up 45 days, 1 user, load average: 0.20, 0.15, 0.10"
    echo ""
    echo "[+] Memory (RAM) Status (simulation):"
    echo "    Total: 8.00 GB | Used: 4.80 GB (60.0%) | Available: 3.20 GB"
    echo "    [ok] RAM headroom is healthy."
    echo ""
    echo "[+] Storage and Disk Headroom (/) (simulation):"
    echo "    Total: 40.00 GB | Free: 18.00 GB | Used: 55%"
    echo "    [ok] Disk headroom is within safe operating parameters."
    echo ""
    echo "[+] Active Docker Containers (simulation):"
    echo "    - nginx-proxy               | Up 12 days           | 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp"
    echo "    - dockhand                  | Up 12 days           | 127.0.0.1:8008->80/tcp"
    echo ""
    echo "=========================================================="
    echo "   Audit Complete: Ready for Operations                  "
    echo "=========================================================="
    exit 0
fi

# Prepare SSH connection arguments
SSH_ARGS=()
if [ -n "$SSH_ALIAS" ]; then
    SSH_ARGS+=("$SSH_ALIAS")
    TARGET_DISPLAY="${TARGET_NAME} (${SSH_ALIAS})"
else
    if [ -n "$SSH_PORT" ]; then
        SSH_ARGS+=("-p" "$SSH_PORT")
        TARGET_DISPLAY="${TARGET_NAME} (${SSH_USER}@${SSH_HOST}:${SSH_PORT})"
    else
        TARGET_DISPLAY="${TARGET_NAME} (${SSH_USER}@${SSH_HOST})"
    fi
    SSH_ARGS+=("${SSH_USER}@${SSH_HOST}")
fi

REMOTE_SCRIPT='echo ===UPTIME===; uptime; echo ===MEMORY===; free -b; echo ===DISK===; df -k /; echo ===DOCKER===; if command -v docker >/dev/null 2>&1; then docker ps --format "{{.Names}}:::{{.Status}}:::{{.Ports}}" 2>/dev/null; else echo NO_DOCKER; fi'

# shellcheck disable=SC2029
if ! RAW_OUTPUT="$(ssh "${SSH_ARGS[@]}" "$REMOTE_SCRIPT" 2>&1)"; then
    echo "[-] Failed to connect or execute remote health audit:" >&2
    echo "$RAW_OUTPUT" >&2
    exit 1
fi

if [ -n "$PYTHON_CMD" ]; then
    RAW_AUDIT_OUTPUT="$RAW_OUTPUT" "$PYTHON_CMD" - "$PROFILE_NAME" "$TARGET_DISPLAY" "$OUTPUT_JSON" "$MAX_RAM_USAGE_PERCENT" "$MIN_FREE_DISK_GB" << 'EOF'
import os, sys, re, json

profile_name = sys.argv[1]
target_display = sys.argv[2]
output_json = int(sys.argv[3])
max_ram = float(sys.argv[4])
min_disk = float(sys.argv[5])

raw_text = os.environ.get("RAW_AUDIT_OUTPUT", "")

# 1. Parse Uptime & Load
uptime_line = ""
uptime_m = re.search(r"===UPTIME===\s*([^\r\n]+)", raw_text)
if uptime_m:
    uptime_line = uptime_m.group(1).strip()

uptime_days = 0
days_m = re.search(r"up\s+(\d+)\s+day", uptime_line)
if days_m:
    uptime_days = int(days_m.group(1))

# 2. Parse Memory
ram_total_gb = 0.0
ram_used_gb = 0.0
ram_avail_gb = 0.0
ram_used_pct = 0.0
ram_warning = False

mem_m = re.search(r"Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)", raw_text)
if mem_m:
    tot_b = float(mem_m.group(1))
    usd_b = float(mem_m.group(2))
    avl_b = float(mem_m.group(6))
    one_gb = 1024.0 * 1024.0 * 1024.0
    ram_total_gb = round(tot_b / one_gb, 2)
    ram_used_gb = round(usd_b / one_gb, 2)
    ram_avail_gb = round(avl_b / one_gb, 2)
    if tot_b > 0:
        ram_used_pct = round((usd_b / tot_b) * 100.0, 1)
    if ram_used_pct >= max_ram:
        ram_warning = True

# 3. Parse Disk
disk_total_gb = 0.0
disk_free_gb = 0.0
disk_pct = 0
disk_critical = False

disk_m = re.search(r"===DISK===[^\r\n]*\r?\n[^\r\n]*\r?\n[^\s]+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+/", raw_text)
if not disk_m:
    disk_m = re.search(r"===DISK===[^\r\n]*\r?\n[^\s]+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+/", raw_text)

if disk_m:
    d_tot_kb = float(disk_m.group(1))
    d_free_kb = float(disk_m.group(3))
    disk_pct = int(disk_m.group(4))
    one_mb_kb = 1024.0 * 1024.0
    disk_total_gb = round(d_tot_kb / one_mb_kb, 2)
    disk_free_gb = round(d_free_kb / one_mb_kb, 2)
    if disk_free_gb < min_disk:
        disk_critical = True

# 4. Parse Docker Containers
docker_containers = []
docker_installed = True
docker_m = re.search(r"===DOCKER===\s*([\s\S]*)$", raw_text)
if docker_m:
    doc_str = docker_m.group(1).strip()
    if doc_str == "NO_DOCKER":
        docker_installed = False
    elif doc_str:
        for line in doc_str.split("\n"):
            line = line.strip()
            if not line:
                continue
            parts = line.split(":::")
            name = parts[0].strip() if len(parts) > 0 else ""
            status = parts[1].strip() if len(parts) > 1 else ""
            ports = parts[2].strip() if len(parts) > 2 else ""
            docker_containers.append({"name": name, "status": status, "ports": ports})

overall_status = "healthy"
if disk_critical:
    overall_status = "critical"
elif ram_warning:
    overall_status = "warning"

if output_json:
    res = {
        "action": "health-audit",
        "profile": profile_name,
        "dry_run": False,
        "status": overall_status,
        "metrics": {
            "uptime_days": uptime_days,
            "uptime": uptime_line,
            "ram_used_percent": ram_used_pct,
            "ram_total_gb": ram_total_gb,
            "ram_avail_gb": ram_avail_gb,
            "disk_total_gb": disk_total_gb,
            "disk_free_gb": disk_free_gb,
            "disk_used_percent": disk_pct,
            "containers_active": len(docker_containers)
        }
    }
    print(json.dumps(res, indent=2))
    sys.exit(0)

# Human-readable output
print("==========================================================")
print("   DevOps Manager: Remote Health and Triage Audit         ")
print(f"   Target: {target_display}")
print("==========================================================")
print("")
print("[+] System Uptime and Load:")
print(f"    {uptime_line}")
print("")
print("[+] Memory (RAM) Status:")
print(f"    Total: {ram_total_gb:.2f} GB | Used: {ram_used_gb:.2f} GB ({ram_used_pct:.1f}%) | Available: {ram_avail_gb:.2f} GB")
if ram_warning:
    print(f"    [!] WARNING: RAM usage exceeds threshold ({max_ram}%)!")
else:
    print("    [ok] RAM headroom is healthy.")
print("")
print("[+] Storage and Disk Headroom (/):")
print(f"    Total: {disk_total_gb:.2f} GB | Free: {disk_free_gb:.2f} GB | Used: {disk_pct}%")
if disk_critical:
    print(f"    [!] CRITICAL: Free disk space ({disk_free_gb:.2f} GB) is below safe minimum ({min_disk:.2f} GB)!")
else:
    print("    [ok] Disk headroom is within safe operating parameters.")
print("")
print("[+] Active Docker Containers:")
if not docker_installed:
    print("    Docker is not installed or not in PATH.")
elif not docker_containers:
    print("    No running containers found.")
else:
    for c in docker_containers:
        print(f"    - {c['name']:<25} | {c['status']:<20} | {c['ports']}")

print("")
print("==========================================================")
print("   Audit Complete: Ready for Operations                  ")
print("==========================================================")
EOF
else
    # Simple output when python is absent
    echo "$RAW_OUTPUT"
    echo "=========================================================="
    echo "   Audit Complete: Ready for Operations                  "
    echo "=========================================================="
fi

exit 0
