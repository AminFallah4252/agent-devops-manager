# Ingress, Reverse Proxy & SSL/TLS Gateway (Nginx)

This runbook covers the architecture, routing rules, SSL/TLS certificate lifecycle, and CDN synchronization for the centralized Nginx Gateway.

---

## 1. Unified Gateway Architecture

All public HTTP (`80`) and HTTPS (`443`) traffic terminates at the **`nginx-proxy`** container located at `/home/ubuntu/nginx-proxy/`.

- **Host Nginx Disabled**: The native host `nginx` service (`systemctl status nginx`) is disabled to prevent port collisions.
- **Certificate Mounts**: Host Let's Encrypt directory `/etc/letsencrypt/` is mounted read-only into `/etc/letsencrypt` inside the container.
- **Site Configurations**: Modifying `/home/ubuntu/nginx-proxy/conf.d/<site>.conf` configures domains dynamically.

```text
Public Internet (Ports 80/443)
       │
       ▼
[Edge CDN: Cloudflare / ArvanCloud] (Edge SSL)
       │
       ▼
[Origin Host: 87.248.153.120]
       │
       ▼
[Container: nginx-proxy] (SNI SSL Termination & Virtual Hosts)
       │
       ├──► http://host.docker.internal:5000 (CryptoRL API)
       ├──► http://host.docker.internal:3050 (Arsh-o-Farsh Demo)
       ├──► http://host.docker.internal:3060 (Clinic Web)
       └──► http://host.docker.internal:3070 (Viki & Chiki Showcase)
```

---

## 2. Standard Virtual Host Template (`conf.d/<site>.conf`)

```nginx
# 1. HTTP Server: Redirect to HTTPS + Handle ACME Challenges
server {
    listen 80;
    server_name myapp.example.com;

    # Mandatory for Certbot HTTP-01 renewals
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# 2. HTTPS Server: SSL Termination & Reverse Proxy
server {
    listen 443 ssl http2;
    server_name myapp.example.com;

    # SSL Certificates (Mounted from host /etc/letsencrypt)
    ssl_certificate /etc/letsencrypt/live/myapp.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myapp.example.com/privkey.pem;
    
    # Modern TLS Ciphers & Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Client body limit (Adjust for file uploads)
    client_max_body_size 25M;

    location / {
        proxy_pass http://host.docker.internal:3050;
        
        # HTTP 1.1 + WebSocket Upgrades
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        # Real Client IP Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

---

## 3. Zero-Downtime Reload SOP

**NEVER restart the container without testing syntax first.** An invalid configuration breaks all public web routing.

```bash
# Step 1: Pre-flight syntax validation
docker compose -f /home/ubuntu/nginx-proxy/docker-compose.yml exec nginx nginx -t

# Step 2: If 'syntax is ok' and 'test is successful', execute zero-downtime reload
docker compose -f /home/ubuntu/nginx-proxy/docker-compose.yml exec nginx nginx -s reload

# Step 3: Verify the domain
curl -k -Iv https://myapp.example.com
```

---

## 4. Let's Encrypt / Certbot Certificate Issuance

When issuing a new certificate on the host using the standalone webroot method:

1. Ensure the HTTP block in Nginx serves `location /.well-known/acme-challenge/` pointing to `/var/www/html`.
2. Run Certbot on the host:
   ```bash
   sudo certbot certonly --webroot -w /home/ubuntu/nginx-proxy/html -d myapp.example.com
   ```
3. Update `conf.d/myapp.example.com.conf` with the certificate paths.
4. Reload Nginx (`nginx -s reload`).

---

## 5. CDN Edge Synchronization (ArvanCloud / Cloudflare)

When traffic routes through a CDN proxy before reaching origin:
1. **SSL Mode**: Always configure **Full (Strict)** or **Full** SSL in the CDN dashboard so edge-to-origin communication is encrypted.
2. **Restoring Real Client IPs**:
   Configure trusted CDN IP ranges in `nginx.conf` (e.g. ArvanCloud CIDRs `185.143.232.0/22`, Cloudflare CIDRs) with `set_real_ip_from` so `$remote_addr` reflects the true visitor rather than the CDN edge node.
