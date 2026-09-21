# Resource & Storage Hygiene Reference Runbook

This runbook establishes strict procedures for keeping cloud VPS instances healthy under storage (e.g. 28 GB disk) and memory (e.g. 4 GB RAM) constraints.

---

## 1. Storage Triage & Headroom Thresholds

| Metric | Safe | Warning | Critical Action |
| :--- | :--- | :--- | :--- |
| **Root Disk Free (`df -h /`)** | `> 5 GB` | `3 GB – 5 GB` | `< 3 GB` — Halt builds; trigger cleanup |
| **Root Disk Usage %** | `< 80%` | `80% – 88%` | `> 90%` — Risk of database write locks |
| **RAM Usage (`free -h`)** | `< 75%` | `75% – 85%` | `> 90%` — High risk of swap thrashing & OOM |
| **Swap Usage** | `< 500 MB` | `500 MB – 1.2 GB`| `> 1.5 GB` — Kernel disk I/O thrashing |

---

## 2. Docker Disk Hygiene Protocol

Docker builds and container logs are the primary cause of sudden disk exhaustion.

### Safe Cleanup (Runs safely without downtime)
```bash
# 1. Prune untagged/dangling images
docker image prune -f

# 2. Prune BuildKit build cache
docker builder prune -f

# 3. Check reclaimed space
df -h /
```

### ⚠️ Forbidden Commands (High Risk)
- **`docker system prune -a --volumes -f`**: **STRICTLY PROHIBITED**. This wipes stopped containers, cached base images, and **all unattached persistent volumes** (destroying application state and databases).
- Only use targeted pruning: `docker image prune` and `docker builder prune`.

---

## 3. Container Log Rotation Enforcement

Uncapped Docker logs write endlessly to `/var/lib/docker/containers/<id>/<id>-json.log`.

### Mandatory `docker-compose.yml` Configuration:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```
*Effect*: Caps logs at 30 MB total per container (3 rotated files of 10 MB each).

### Emergency Log Truncation
If a container log has already grown to multiple gigabytes:
```bash
# Locate largest container logs
du -ah /var/lib/docker/containers/ | sort -rh | head -n 10

# Zero out the log file safely without restarting the container
truncate -s 0 /var/lib/docker/containers/<container_id>/<container_id>-json.log
```

---

## 4. Host System Storage Hygiene

Run periodically during routine server maintenance:

```bash
# 1. Vacuum systemd journal logs older than 7 days
sudo journalctl --vacuum-time=7d

# 2. Clean apt package manager cache
sudo apt-get clean

# 3. Remove obsolete kernel headers and packages
sudo apt-get autoremove -y

# 4. Clean temporary files
sudo rm -rf /tmp/* /var/tmp/*
```

---

## 5. Memory & Swap Optimization

When running multiple services on a 4 GB RAM VPS:
1. **Swap Allocation**: Ensure at least **2 GB swap** is enabled as an emergency buffer:
   ```bash
   swapon --show
   ```
2. **Swappiness Tuning**: Set `vm.swappiness = 10` or `20` in `/etc/sysctl.conf` so Linux prefers freeing page cache over swapping active memory pages.
3. **Runtime GC Constraints**:
   - For .NET applications: Set `DOTNET_gcServer=0` (Workstation GC) and `DOTNET_GCHeapHardLimitPercent=60` in `.env` to prevent the runtime from claiming all available RAM.
   - For Node.js applications: Set `--max-old-space-size=256` or `512`.
