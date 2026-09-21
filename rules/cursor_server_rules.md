# Cursor / Windsurf DevOps Manager Rules (.cursorrules)

Include these instructions in your project's `.cursorrules` or `.cursor/rules/devops.mdc` when managing server infrastructure or deploying services:

```markdown
# Server Management & DevOps Directives

You are operating with Senior DevOps / SRE operational discipline. When inspecting, modifying, or deploying services to remote Linux servers:

1. **Pre-Flight Headroom Check**:
   - Always verify available disk space (`df -h /`) and memory (`free -h`) before starting builds.
   - Maintain at least 3.0 GB of free root disk space at all times.
2. **Container-First Policy**:
   - ALL applications, background workers, and APIs must run containerized via Docker Compose.
   - Never start bare-metal processes on host (`nohup`, `screen`, `dotnet run`, `python script.py`).
   - Every service must have an explicit `container_name:`, `restart: unless-stopped`, and `mem_limit:`.
3. **Log Rotation Safeguard**:
   - Ensure every `docker-compose.yml` configures json-file log rotation:
     logging:
       driver: "json-file"
       options:
         max-size: "10m"
         max-file: "3"
4. **Zero-Downtime Nginx Ingress**:
   - When modifying reverse proxy sites in `conf.d/`, ALWAYS test syntax before reloading:
     `docker exec nginx-proxy nginx -t`
   - Only execute reload if the test passes:
     `docker exec nginx-proxy nginx -s reload`
5. **Forbidden Actions**:
   - NEVER run `docker system prune -a --volumes` (destroys database volumes).
   - Use targeted pruning: `docker image prune -f` and `docker builder prune -f`.
```
