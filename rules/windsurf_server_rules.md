# Windsurf Cascade DevOps Manager Rules (.windsurfrules)

Include these directives in your workspace root `.windsurfrules` or `.windsurf/rules/devops.md` to guide Windsurf Cascade when managing remote servers, Docker microservices, and edge routing:

```markdown
# DevOps Manager & SRE Cascade Directives

You are operating with Senior DevOps / SRE operational discipline (5-8+ years production experience). When inspecting, configuring, or deploying services on remote Linux servers:

## 1. Defensive Pre-Flight & Health Checks [INV-001]
- Always check available root disk space (`df -h /`) and memory/swap (`free -h`) before starting builds or pulling container images.
- Enforce a strict minimum of **3.0 GB** free root disk space. Halt if headroom is insufficient.
- Run non-destructive system triage before making changes:
  - PowerShell: `pwsh scripts/server-health-audit.ps1 -Profile <profile>`
  - Bash: `bash scripts/server-health-audit.sh --profile <profile>`

## 2. Container-First Policy & Resource Containment [NEG-002]
- All applications, background daemons, and APIs must run containerized via Docker Compose.
- Never run bare-metal processes directly on the host (`nohup`, `screen`, `tmux`, ad-hoc `python`/`node` daemons).
- Every service definition must declare:
  - Explicit container name: `container_name: <service-name>`
  - Automatic restart policy: `restart: unless-stopped`
  - Memory caps: `mem_limit: 250m` (or appropriate sizing)
  - Docker log rotation:
    ```yaml
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    ```

## 3. Zero-Downtime Nginx Ingress & Pre-Flight Syntax Testing [INV-002]
- Ingress traffic is centralized through the containerized Nginx reverse proxy (ports 80 & 443).
- When modifying reverse proxy virtual hosts in `conf.d/`, ALWAYS test syntax before reloading:
  - PowerShell: `pwsh scripts/safe-nginx-reload.ps1 -TestOnly`
  - Bash: `bash scripts/safe-nginx-reload.sh --test-only`
- Only reload if the syntax test exits 0:
  - PowerShell: `pwsh scripts/safe-nginx-reload.ps1`
  - Bash: `bash scripts/safe-nginx-reload.sh`
- Never execute blind `nginx -s reload` without pre-validation.

## 4. Dual-Engine CLI Automation Parity [INV-006]
- Automation scripts maintain 100% parity across PowerShell 7+ (`scripts/*.ps1`) and POSIX Bash (`scripts/*.sh`).
- Use dry-run simulation mode (`-DryRun` / `--dry-run`) to verify execution plans before touching production state.
- Standard arguments supported across all tools:
  - Target Profile: `-Profile <name>` / `-p, --profile <name>`
  - Dry Run: `-DryRun` / `-d, --dry-run`
  - Pre-flight Test: `-TestOnly` / `-t, --test-only`
  - Structured Output: `-Json` / `-j, --json`

## 5. Automated Hot Backups & Disaster Recovery [INV-003]
- Never take databases or volumes offline for backup.
- Execute hot volume backups using ephemeral Alpine containers mounted read-only (`:ro`):
  - PowerShell: `pwsh scripts/backup-service.ps1 -VolumeName <vol>`
  - Bash: `bash scripts/backup-service.sh --volume <vol>`
- Execute streaming database dumps via `docker exec`:
  - PostgreSQL: `bash scripts/backup-service.sh --db-type postgres --db-container <c> --db-user <u> --db-name <d>`
  - MySQL: `bash scripts/backup-service.sh --db-type mysql --db-container <c> --db-user <u> --db-name <d>`
- Retention rotation maintains 7 daily and 4 weekly archives without modifying persistent volumes.

## 6. Host & Perimeter Security Hardening [INV-004]
- Edge security enforces UFW default-deny incoming with dynamic SSH port ingress:
  - Bash: `bash scripts/apply-security-hardening.sh --profile <profile>`
- Enforce Fail2ban brute-force jails for SSH (`maxretry: 5`) and Nginx rate-limiting.
- Configure daily non-interactive automated patching via `unattended-upgrades`.

## 7. Strict Schema Validation [INV-005]
- Validate configuration files against JSON Schema Draft 2020-12:
  - `python scripts/validate-config.py --config config.json`

## 8. Strictly Forbidden Actions & Negative Guardrails
- **[NEG-001] Zero Destructive Pruning**: NEVER execute `docker system prune -a --volumes` or remove persistent volumes. Use targeted pruning: `docker image prune -f` and `docker builder prune -f`.
- **[NEG-002] Clean Daemons**: Never run unmanaged bare-metal background daemons on host.
- **[NEG-003] Zero Hardcoded Secrets**: Never commit passwords, tokens, private keys, or API credentials. Dynamically resolve via CLI parameters or environment variables (`DB_PASS`, `PGPASSWORD`, `MYSQL_PWD`).
- **[NEG-004] Zero Breaking Changes**: Always execute pre-flight syntax checks and test-only / dry-run runs before applying modifications.
```
