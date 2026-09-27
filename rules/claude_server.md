# Claude Code DevOps Manager Rules (CLAUDE.md)

Include these instructions in your project's root `CLAUDE.md` to guide Claude Code when managing remote servers, Docker environments, and CI/CD pipelines:

```markdown
# Senior DevOps & Server Management Guidelines

Follow strict Senior DevOps / SRE operational standards (5-8+ years production discipline) when interacting with Linux servers, containerized workloads, and edge routing:

## 1. Safety & Pre-Flight Checks [INV-001]
- Check available disk space (`df -h /`) before building images or pulling layers. Halt immediately if free space < 3.0 GB.
- Inspect memory and swap (`free -h`) to prevent kernel OOM freezes.
- Run non-destructive health triage before altering server state:
  - PowerShell: `pwsh scripts/server-health-audit.ps1`
  - Bash: `bash scripts/server-health-audit.sh`

## 2. Strict Container Standards [NEG-002]
- All workloads must run in Docker Compose with explicit `container_name:`, `restart: unless-stopped`, and `mem_limit:`.
- Enforce Docker log rotation (`max-size: 10m`, `max-file: 3`) on every service to prevent root partition exhaustion.
- Never run untracked bare-metal processes on host (`nohup`, `screen`, unmanaged background scripts).

## 3. Reverse Proxy & Zero-Downtime Nginx Ingress [INV-002]
- Containerized Nginx handles public ingress (ports 80 & 443).
- Always dry-run syntax check (`nginx -t`) before reloading Nginx (`nginx -s reload`):
  - PowerShell: `pwsh scripts/safe-nginx-reload.ps1 -TestOnly`
  - Bash: `bash scripts/safe-nginx-reload.sh --test-only`
- Execute graceful zero-downtime reload only when syntax validation passes:
  - PowerShell: `pwsh scripts/safe-nginx-reload.ps1`
  - Bash: `bash scripts/safe-nginx-reload.sh`
- Mount Let's Encrypt certificates read-only (`:ro`).

## 4. Dual-Engine CLI Automation Parity [INV-006]
- Automation scripts maintain 100% parity across PowerShell 7+ (`scripts/*.ps1`) and POSIX Bash (`scripts/*.sh`).
- Common operational flags supported across all scripts:
  - `-Profile <name>` / `-p, --profile <name>`: Target server profile from `config.json`.
  - `-DryRun` / `-d, --dry-run`: Dry-run simulation without touching server state [NEG-004].
  - `-TestOnly` / `-t, --test-only`: Pre-flight verification check only.
  - `-Json` / `-j, --json`: Machine-readable structured JSON output.

## 5. Automated Hot Backups & Disaster Recovery [INV-003]
- Back up named Docker volumes hot using ephemeral Alpine containers mounted read-only (`:ro`):
  - PowerShell: `pwsh scripts/backup-service.ps1 -VolumeName <vol>`
  - Bash: `bash scripts/backup-service.sh --volume <vol>`
- Stream database dumps directly to compressed `.sql.gz` archives:
  - PostgreSQL: `bash scripts/backup-service.sh --db-type postgres --db-container <c> --db-user <u> --db-name <d>`
  - MySQL: `bash scripts/backup-service.sh --db-type mysql --db-container <c> --db-user <u> --db-name <d>`
- Automated dual-tier retention prunes archives older than 28 days (retaining 7 daily and 4 weekly snapshots) without touching active volumes.

## 6. Host & Perimeter Security Hardening [INV-004]
- Enforce UFW default-deny incoming policy with dynamic SSH port allow, web ingress (80/443), and Docker bridge (`docker0`) traffic:
  - Bash: `bash scripts/apply-security-hardening.sh --profile <profile>`
- Deploy Fail2ban intrusion prevention for SSH brute-force protection (`maxretry: 5`, `bantime: 1h`) and Nginx rate-limiting.
- Enable automatic daily security patch installation via `unattended-upgrades`.

## 7. Strict Configuration Validation [INV-005]
- Validate configuration files against JSON Schema Draft 2020-12:
  - CLI: `python scripts/validate-config.py --config config.json`

## 8. Test Suite Execution Commands
When contributing or verifying changes, execute all localized test suites:
- **PowerShell Pester v5**: `Invoke-Pester -Path ./tests/powershell/ -Output Detailed`
- **POSIX Bash Harness**: `bash tests/bash/test_runner.sh`
- **Static Analysis & Linting**: `bash tests/lint.sh`
- **Python Schema Validation**: `pytest tests/python/test_validate_config.py`

## 9. Non-Destructive Constraints & Negative Guardrails
- **[NEG-001] Zero Destructive Pruning**: NEVER run `docker system prune -a --volumes` or delete persistent volumes. Use targeted `docker image prune -f` and `docker builder prune -f`.
- **[NEG-002] Clean Daemons**: Never start unmanaged host background processes.
- **[NEG-003] Zero Hardcoded Secrets**: Never commit passwords, tokens, or credentials. Resolve dynamically from environment variables (`DB_PASS`, `PGPASSWORD`, `MYSQL_PWD`).
- **[NEG-004] Zero Breaking Changes**: All operations must support dry-run simulation and pre-flight checks.
```
