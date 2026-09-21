# Safety Guardrails & Operational Audit

This document enforces defensive guardrails, forbidden commands, and audit standards for all automated and agent-driven server operations.

---

## ⛔ Strictly Forbidden Commands & Actions

The following commands are strictly prohibited in automated scripts and agent executions:

| Forbidden Action | Why It Is Dangerous | Safe Alternative |
| :--- | :--- | :--- |
| `docker system prune -a --volumes -f` | Destroys all stopped containers, caches, and **all unattached database volumes**. | Use `docker image prune -f` and `docker builder prune -f`. |
| `rm -rf /` or recursive deletions of `/var/`, `/etc/`, `/home/` | Unrecoverable OS corruption. | Delete specific named files or directories only. |
| Directly editing `/etc/ssh/sshd_config` without backup | Potential lock-out from remote SSH access. | Create `.bak` first, test with `sshd -t` before restarting daemon. |
| Running bare-metal apps (`nohup`, `dotnet run`, `python main.py`) | Untracked memory usage, bypasses Dockhand, causes OOM. | Must use Docker Compose with explicit `mem_limit`. |
| Blind Nginx reload without `nginx -t` | Invalid syntax breaks all public website traffic. | Always run `nginx -t` dry-run test first. |

---

## 🛡️ Pre-Flight Verification Checklist

Before applying any change to a production server, verify:

- [ ] **1. Disk Headroom**: Is root filesystem free space `>= 3.0 GB`?
- [ ] **2. Memory Budget**: Is free RAM + swap sufficient to support the build and runtime?
- [ ] **3. Port Conflicts**: Has the port allocation been checked against active listeners (`ss -tulpn`)?
- [ ] **4. Container Naming**: Does the service specify an explicit `container_name`?
- [ ] **5. Log Limits**: Are log rotation rules (`max-size: 10m`, `max-file: 3`) defined in Compose?
- [ ] **6. Volume Protection**: Are persistent directories mapped to dedicated named volumes or bind mounts?

---

## 📝 Operational Audit & Topology Synchronization

Whenever an agent or engineer adds, modifies, or decommissions a service or port on a server:

1. **Update Central Topology (`resource.md`)**:
   - Record the allocated port, container name, memory limits, and domain mappings in the central server inventory document.
2. **Commit Configuration Changes**:
   - Commit any updated `docker-compose.yml`, Nginx `.conf` files, or monitoring alerts to Git version control.
3. **Verify Health State**:
   - Confirm Dockhand reports status 🟢 `Healthy` or `Running`.
