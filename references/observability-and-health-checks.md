# Observability & System Health Checks

This guide defines the observability architecture, real-time diagnostic commands, and health verification procedures across host and container layers.

---

## 1. Observability Stack Architecture

A lightweight observability stack monitors host metrics, container performance, and operational logs without consuming excessive CPU or RAM:

```text
Host Layer                     Metrics Aggregation             Visualization
──────────                     ───────────────────             ─────────────
[Node Exporter :9100]  ──►     [Prometheus :9090]      ──►     [Grafana :3000]
(Linux CPU/RAM/Disk/Net)       (Scrapes every 15s)             (Telemetry Dashboards)
                                       ▲
[cAdvisor :8080]       ────────────────┘
(Container CPU/Memory)

Container Engine                                               Management UI
────────────────                                               ─────────────
[Docker Daemon]        ───────────────────────────────►        [Dockhand :8008]
                                                               (Container Dashboard)
```

---

## 2. Real-Time Triage Command Matrix

When responding to alerts or inspecting server health:

### 1. Overall System Load & Uptime
```bash
uptime
# Check 1m, 5m, 15m load averages against core count (e.g. 2 vCPU -> load < 2.0 is healthy)
```

### 2. Memory & Swap Breakdown
```bash
free -h
# Evaluates total, used, free, shared, buff/cache, and available memory
```

### 3. Top Memory Consumers
```bash
ps aux --sort=-%mem | head -n 10
```

### 4. Container Resource Footprints
```bash
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}"
```

### 5. Disk Headroom & Inodes
```bash
df -h /
df -i /
# Always check inodes (-i): A disk can report free GB but be locked if 100% of inodes are exhausted
```

### 6. Active Network Listeners
```bash
ss -tulpn | grep LISTEN
```

---

## 3. Dockhand Container Management Standard

The **Dockhand** management UI provides an instant web overview of all services:
- **Default Port**: Bound to `127.0.0.1:8008` (accessible via SSH tunnel or reverse proxy domain).
- **Status Indicators**:
  - 🟢 **Healthy / Running**: Container is actively serving requests.
  - 🟡 **Starting / Unhealthy**: Health check failed; review `docker compose logs`.
  - 🔴 **Exited / Restarting**: Crash loop detected; check exit code (`docker ps -a`).

---

## 4. Health Check Implementation in Docker Compose

Always embed an explicit `healthcheck` definition in production services:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 20s
```

*Benefit*: Docker marks the service as `healthy` only after application initialization completes, preventing traffic from routing to an unready container.
