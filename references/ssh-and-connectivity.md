# SSH & Remote Connectivity Reference Runbook

This guide details secure, zero-leak SSH connectivity standards, key management, custom daemon ports, network persistence, and local port tunneling for remote private dashboards.

---

## 1. Zero-Leak Credential Architecture

- **Public Key Authentication Only**: Password authentication on public internet servers must be disabled (`PasswordAuthentication no`).
- **Key Location**: Private keys must reside strictly in protected user directories (`~/.ssh/id_rsa`, `~/.ssh/id_ed25519` on Linux/macOS, or `C:\Users\<user>\.ssh\` on Windows) with strict NTFS / POSIX permissions (`chmod 600`).
- **Never Embed Keys in Repositories or Logs**: Never pass raw private keys or credentials inside Git repositories, command strings, or conversation transcripts.
- **SSH Config Multiplexing**: All target hosts should be mapped cleanly inside `~/.ssh/config` using aliases.

---

## 2. Production `~/.ssh/config` Pattern

Example configuration for a hardened server listening on custom port `9011` with keep-alive:

```ssh-config
# Primary remote management session
Host hephaest
    HostName 87.248.153.120
    User ubuntu
    Port 9011
    IdentityFile ~/.ssh/id_rsa
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 15
    ServerAliveCountMax 3
    TCPKeepAlive yes

# Dedicated UI Tunnel alias (for forwarding internal dashboards)
Host hephaest-tunnel
    HostName 87.248.153.120
    User ubuntu
    Port 9011
    IdentityFile ~/.ssh/id_rsa
    IdentityFile ~/.ssh/id_ed25519
    LocalForward 8008 127.0.0.1:8008     # Dockhand UI
    LocalForward 3000 127.0.0.1:3000     # Grafana
    LocalForward 19090 127.0.0.1:9090    # Prometheus (avoiding Windows reserved ports)
    ServerAliveInterval 15
    ServerAliveCountMax 3
```

---

## 3. Local Port Forwarding (SSH Tunneling)

### Why Tunnel Instead of Public Ports?
Administrative UIs (Dockhand, Portainer, Prometheus, Grafana, cAdvisor) expose powerful controls. Exposing them directly on public ports `0.0.0.0` invites brute-force and vulnerability scans.
- **Best Practice**: Bind admin containers to `127.0.0.1:<PORT>` on the host.
- **Access Method**: Forward the port dynamically via an SSH tunnel:
  ```bash
  ssh -N -L 8008:127.0.0.1:8008 -p <PORT> <USER>@<HOST>
  ```
  Then access `http://localhost:8008` securely in your browser.

### Windows Hyper-V Port Reservation Gotcha
On Windows machines with Hyper-V or WSL2 enabled, certain port ranges (commonly `9015`–`9114`) are dynamically reserved by the OS kernel:
- Attempting to bind `LocalForward 9090` may fail with `bind [127.0.0.1]:9090: Permission denied`.
- **Solution**: Map the local port outside the reserved range (e.g. `LocalForward 19090 127.0.0.1:9090`), then open `http://localhost:19090`.

---

## 4. Non-Standard SSH Port Hardening

Running SSH on a non-standard port (e.g. `9011` instead of `22`) eliminates 99% of automated credential stuffing bots:
1. Ensure the custom port is allowed in firewall:
   ```bash
   sudo ufw allow 9011/tcp
   ```
2. Update `/etc/ssh/sshd_config`:
   ```text
   Port 9011
   PermitRootLogin no
   PasswordAuthentication no
   ```
3. Test daemon syntax before restarting:
   ```bash
   sudo sshd -t
   ```
4. Restart SSH service:
   ```bash
   sudo systemctl restart ssh
   ```
5. **Always test a new connection in a separate terminal before closing your existing session.**
