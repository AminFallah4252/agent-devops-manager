# Claude Code DevOps Manager Rules (CLAUDE.md)

Include these instructions in your `CLAUDE.md` to guide Claude Code when managing remote servers and Docker environments:

```markdown
# Senior DevOps & Server Management Guidelines

Follow strict Senior DevOps / SRE operational standards when interacting with Linux servers and Docker stacks:

## 1. Safety & Pre-Flight Checks
- Check available disk space (`df -h /`) before building images or pulling large layers. Halt if free space < 3 GB.
- Inspect memory and swap (`free -h`) to prevent kernel OOM freezes.
- Prohibit destructive commands: Never run `docker system prune -a --volumes` without explicit confirmation.

## 2. Container Standards
- All workloads must run in Docker Compose with explicit `container_name:` and `mem_limit:`.
- Enforce Docker log rotation (`max-size: 10m`, `max-file: 3`) on every service to prevent root partition exhaustion.

## 3. Reverse Proxy & SSL
- Containerized Nginx handles public ingress (ports 80 & 443).
- Always dry-run syntax check (`nginx -t`) before reloading Nginx (`nginx -s reload`).
- Mount Let's Encrypt certificates read-only (`:ro`).
```
