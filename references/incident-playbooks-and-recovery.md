# Incident Playbooks & Emergency Recovery

Step-by-step diagnostic and remediation playbooks for common production server incidents.

---

## 🚨 Playbook 1: Out-Of-Memory (OOM) Freeze & Swap Thrashing

### Symptoms:
- SSH connection hangs or takes > 30 seconds to authenticate.
- Host feels sluggish; `top` shows high `%wa` (I/O wait) due to excessive swapping.
- `dmesg | grep -i oom` shows Linux kernel killed a process.

### Step-by-Step Remediation:
1. **Identify the Memory Culprit**:
   ```bash
   docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
   ps aux --sort=-%mem | head -n 5
   ```
2. **Gracefully Restart Culprit Container**:
   ```bash
   docker restart <culprit_container>
   ```
3. **Impose Strict Memory Limit**:
   If the container lacked memory caps, edit its `docker-compose.yml`:
   ```yaml
   mem_limit: 300m
   memswap_limit: 600m
   ```
   Apply immediately:
   ```bash
   docker compose up -d --no-deps <culprit_service>
   ```
4. **Reclaim Buffer Memory**:
   ```bash
   sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
   ```

---

## 🚨 Playbook 2: Disk Full ("No space left on device")

### Symptoms:
- Docker builds fail with `write /var/lib/docker/...: no space left on device`.
- Databases enter read-only mode.
- System services fail to start.

### Step-by-Step Remediation:
1. **Immediate Headroom Recovery**:
   ```bash
   # Remove dangling images & build caches
   docker image prune -f
   docker builder prune -f
   
   # Truncate large journal logs
   sudo journalctl --vacuum-size=100M
   sudo apt-get clean
   ```
2. **Locate Runaway Files**:
   ```bash
   # Find top 10 largest directories on root
   du -hx / | sort -rh | head -n 10
   ```
3. **Check for Un-rotated Docker Logs**:
   ```bash
   find /var/lib/docker/containers/ -name "*-json.log" -size +100M -exec truncate -s 0 {} +
   ```

---

## 🚨 Playbook 3: 502 Bad Gateway / Ingress Routing Failure

### Symptoms:
- Browser displays `502 Bad Gateway` on a domain or subdomain.

### Step-by-Step Remediation:
1. **Check Nginx Container Logs**:
   ```bash
   docker compose -f /home/ubuntu/nginx-proxy/docker-compose.yml logs --tail=30
   ```
2. **Verify Target Application Container is Running**:
   ```bash
   docker ps | grep <app_name>
   ```
   If stopped, inspect exit logs: `docker logs --tail=50 <app_container>`.
3. **Verify Upstream Port Reachability**:
   Test reachability directly on host:
   ```bash
   curl -I http://127.0.0.1:<PORT>
   ```
4. **Verify Nginx Upstream Configuration**:
   Inspect `/home/ubuntu/nginx-proxy/conf.d/<domain>.conf`:
   - If using `http://host.docker.internal:<PORT>`, ensure `nginx-proxy/docker-compose.yml` includes `extra_hosts: ["host.docker.internal:host-gateway"]`.
   - If using container name (e.g. `http://myapp:3000`), ensure both containers share the same Docker network.

---

## 🚨 Playbook 4: Container Restart Loop (CrashLoopBackOff)

### Symptoms:
- `docker ps` shows container status `Restarting (1)` or `Restarting (137)`.

### Step-by-Step Remediation:
1. **Check Exit Code**:
   ```bash
   docker inspect <container_name> --format='{{.State.ExitCode}}'
   ```
   - **Exit Code 137**: Process was killed by OS kernel (OOM). Increase `mem_limit` or fix memory leak in application.
   - **Exit Code 1**: Application threw an unhandled exception or missing environment variable.
2. **Examine Container Crash Logs**:
   ```bash
   docker logs --tail=100 <container_name>
   ```
3. **Check Environment Variables**:
   Validate `.env` file syntax and required connection strings.
4. **Interactive Debugging**:
   Run container with an overridden entrypoint to inspect filesystem:
   ```bash
   docker run --rm -it --entrypoint sh <image_name>
   ```
