# Contributing to Agent DevOps Manager

Thank you for your interest in contributing to **Agent DevOps Manager**! This project provides enterprise-grade, defensive DevOps and SRE operational capabilities for AI coding agents and platform engineering teams.

---

## 🛠️ Local Development Environment Setup

To maintain multi-platform adapter parity and run all test harnesses locally, ensure your environment meets the following requirements:

1. **PowerShell 7+ (`pwsh`) & Pester v5**:
   - Install PowerShell 7+ on Windows, macOS, or Linux.
   - Install Pester v5:
     ```powershell
     Install-Module -Name Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
     ```

2. **POSIX Bash & ShellCheck**:
   - On Linux/macOS: Native Bash 4+ and `shellcheck` (`apt-get install shellcheck` or `brew install shellcheck`).
   - On Windows: Git Bash or WSL 2.

3. **Python 3.9+ & Pytest**:
   - Python 3.9 or newer.
   - Install test dependencies:
     ```bash
     pip install pytest jsonschema
     ```

---

## 🧪 Running the Local Test Suites

All pull requests must pass 100% of local test suites before merging.

### 1. PowerShell Pester v5 Test Suite
Executes unit and mock integration tests for all `.ps1` automation scripts in `scripts/`:
```powershell
Invoke-Pester -Path ./tests/powershell/ -Output Detailed
```
*Expected Output*: 40/40 tests passing across `BackupService`, `DockerCleanup`, `SafeNginxReload`, `ServerHealthAudit`, and `ServerSshTunnel`.

### 2. POSIX Bash Test Suite Runner
Executes POSIX-compliant unit and integration tests across all `.sh` automation scripts:
```bash
bash tests/bash/test_runner.sh
```
*Expected Output*: 6/6 test suites passing (139 tests) without failures.

### 3. Static Analysis, ShellCheck & JSON Schema Lint Harness
Runs ShellCheck across all 14 bash scripts and verifies JSON syntax and configuration schema conformity:
```bash
bash tests/lint.sh
```
*Expected Output*:
- `[OK]` for all shell scripts in `scripts/`, `tests/bash/`, and `tests/lint.sh`.
- `[OK]` for all JSON files in the repository.
- `[OK] config.template.json conforms to schemas/config.schema.json`.
- `[OK] tests/fixtures/test-config.json conforms to schemas/config.schema.json`.

### 4. Python Configuration Schema Validation Suite
Verifies `schemas/config.schema.json` and `scripts/validate-config.py`:
```bash
pytest tests/python/test_validate_config.py
```
*Expected Output*: 37/37 tests passing without errors.

---

## 🛡️ Invariant Compliance & Guardrails for New PRs

Every proposed change or new feature must uphold the project's core invariants and negative constraints:

### Architectural Invariants:
1. **[INV-001] Non-Destructive Health Auditing**: System triage scripts must inspect CPU, RAM, disk headroom ($\ge 3.0$ GB), Docker status, and ports non-destructively.
2. **[INV-002] Zero-Downtime Nginx Ingress**: Reverse proxy modifications must execute pre-flight syntax checks (`nginx -t`) inside the container before executing reload (`nginx -s reload`).
3. **[INV-003] Automated Backup & Disaster Recovery**: Named Docker volume backups must mount volumes read-only (`:ro`) via ephemeral Alpine containers. Database dumps must stream directly via `docker exec`. Retention rotation must isolate archives (7 daily, 4 weekly) without deleting persistent volumes.
4. **[INV-004] Host & Edge Security Hardening**: Security configurations must enforce UFW default-deny incoming, dynamic SSH port allow, Docker bridge traffic (`docker0`), Fail2ban jails (`[sshd]`, `[nginx-req-limit]`), and unattended-upgrades.
5. **[INV-005] Strict Configuration Schema Validation**: Any new configuration parameter in `config.template.json` must have a corresponding schema definition in `schemas/config.schema.json` (Draft 2020-12) and pass `validate-config.py`.
6. **[INV-006] Multi-Platform Adapter Parity**: Every new operational capability must be provided in **both PowerShell 7+ (`.ps1`) and POSIX Bash (`.sh`)** where applicable, and synchronized across `SKILL.md`, `rules/cursor_server_rules.md`, `rules/claude_server.md`, and `rules/windsurf_server_rules.md`.

### Negative Guardrails (Strictly Prohibited):
- **[NEG-001] Zero Destructive Pruning**: PRs MUST NEVER introduce `docker system prune -a --volumes` or commands that delete persistent Docker volumes.
- **[NEG-002] Clean Daemons**: PRs MUST NOT add bare-metal host daemons (`nohup`, `screen`, unmanaged systemd apps). All long-running applications must be containerized in Docker Compose with memory caps (`mem_limit`) and log rotation (`max-size: 10m`, `max-file: 3`).
- **[NEG-003] Zero Hardcoded Secrets**: PRs MUST NOT introduce hardcoded passwords, tokens, API keys, or private IP addresses. Credentials must be resolved dynamically via environment variables (`DB_PASS`, `PGPASSWORD`, `MYSQL_PWD`) or CLI flags.
- **[NEG-004] Zero Breaking Changes**: All scripts must provide `--dry-run` / `-DryRun` simulation mode and `--test-only` / `-TestOnly` pre-flight modes.

---

## 📝 Conventional Commit Guidelines

We enforce the [Conventional Commits](https://www.conventionalcommits.org/) specification for clear, semantic git histories.

### Commit Format:
```text
<type>(<scope>): <short description>

[optional body with details & invariant tags]
```

### Allowed Types:
- `feat`: A new operational script, CLI feature, or platform adapter rule.
- `fix`: Bug fix in automation scripts, test suites, or configuration schemas.
- `docs`: Documentation updates (`README.md`, `SKILL.md`, references, rules).
- `test`: Adding or refactoring Pester, Bash, or Pytest specifications.
- `refactor`: Code changes that neither fix a bug nor add a feature.
- `perf`: Performance optimizations in script execution or log parsing.
- `chore`: Maintenance tasks, dependency updates, or linting tweaks.

### Recommended Scopes:
- `backup`: Hot volume and database backup engine (`backup-service`).
- `security`: Host hardening, UFW firewall, Fail2ban, sysctl (`apply-security-hardening`).
- `schema`: Configuration schema and validation CLI (`validate-config.py`, `config.schema.json`).
- `nginx`: Reverse proxy routing and reload automation (`safe-nginx-reload`).
- `docker`: Container standards, hygiene, and pruning (`docker-cleanup`).
- `audit`: System health audit and triage (`server-health-audit`).
- `tunnel`: SSH port forwarding and UI tunneling (`server-ssh-tunnel`).
- `adapters`: Multi-platform rules for Antigravity, Cursor, Claude Code, and Windsurf.
- `powershell`: PowerShell script engine.
- `bash`: POSIX Bash script engine.
- `tests`: Test suites and harness runners.

### Commit Examples:
```text
feat(backup): add streaming mysql database dump support [INV-003, NEG-003]
fix(nginx): prevent syntax check subshell exit code swallowing [INV-002]
docs(adapters): synchronize cursor and windsurf rules for sprint 3 [INV-006]
test(powershell): add dry-run contract test for server health audit
```

---

## 🚀 Pre-Submission Quality Gate Checklist

Before opening a pull request, run the following verification checklist:

- [ ] All PowerShell Pester v5 tests pass (`Invoke-Pester -Path ./tests/powershell/ -Output Detailed`).
- [ ] All POSIX Bash tests pass (`bash tests/bash/test_runner.sh`).
- [ ] Static linting passes ShellCheck and JSON validation (`bash tests/lint.sh`).
- [ ] Python schema validation tests pass (`pytest tests/python/test_validate_config.py`).
- [ ] Dual-engine parity is maintained between `.ps1` and `.sh` scripts.
- [ ] Multi-platform adapter rules (`SKILL.md`, `rules/cursor_server_rules.md`, `rules/claude_server.md`, `rules/windsurf_server_rules.md`) are synchronized.
- [ ] No hardcoded secrets, passwords, or tokens are introduced [NEG-003].
- [ ] No destructive pruning commands or persistent volume deletions [NEG-001].
