# Contributing to DevOps Manager

Thank you for your interest in improving the **DevOps Manager** agent skill and runbook!

## How to Contribute

1. **New Reference Playbooks**:
   - If you encounter a recurring production failure pattern (e.g., specific database deadlocks, Redis memory exhaustion, SSL renewal edge cases), document it inside `references/incident-playbooks-and-recovery.md` or as a new modular reference in `references/`.
2. **Platform & Cloud Adapters**:
   - We welcome contributions adding support for systemd services, Kubernetes lightweight runners (K3s), Cloudflare Tunnels, Caddy server alternatives, and multi-cloud providers (Hetzner, AWS, DigitalOcean).
3. **Cross-Platform Scripts**:
   - When submitting scripts for `scripts/`, ensure both PowerShell 7+ and POSIX Bash compatibility.
   - All scripts must operate non-destructively by default and never leak secrets.

## Standards & Guidelines
- **Zero-Downtime First**: All web server and reverse proxy modifications must be accompanied by pre-flight syntax checks (`nginx -t`).
- **Defensive Resource Caps**: All proposed container templates must declare explicit memory caps (`mem_limit`) and log rotation limits.
- **Privacy & Security**: Never commit IP addresses, private domains, SSH keys, or access tokens.
