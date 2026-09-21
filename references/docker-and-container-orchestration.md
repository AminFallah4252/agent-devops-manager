# Docker & Container Orchestration Standards

This document establishes the production container standards required for all services, microservices, background workers, and dashboards deployed on managed servers.

---

## 1. The Container-Only Architecture

Bare-metal processes running directly on the host OS (`nohup`, `screen`, `tmux`, manual `dotnet run`, `python script.py`, or arbitrary `systemd` app units) are **strictly prohibited**.

### Core Rationale:
1. **Dockhand / UI Visibility**: All running workloads must be visible, inspectable, and manageable from centralized container management tools (e.g. Dockhand at `http://127.0.0.1:8008`).
2. **Resource Containment**: Bare-metal processes can consume 100% of host RAM, triggering an unmanaged kernel OOM freeze.
3. **Reproducibility & Rollback**: Container images and compose manifests provide atomic deployment and rollback.

---

## 2. Production `docker-compose.yml` Specification

Every service deployed to the server must adhere to this standardized schema:

```yaml
version: '3.8'

services:
  app-service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: demo-service-prod
    restart: unless-stopped
    
    # 1. Resource Limits (Mandatory on constrained VPS)
    mem_limit: 256m
    memswap_limit: 512m
    cpus: 1.0

    # 2. Port Binding
    ports:
      # If routed through Nginx proxy, bind to loopback to prevent public exposure
      - "127.0.0.1:3050:3050"

    # 3. Environment & Secrets
    env_file:
      - .env

    # 4. Mandatory Log Limits (Prevents runaway JSON logs from filling disk)
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # 5. Health Check (Enables self-healing and accurate Dockhand status)
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3050/health || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s

    # 6. Isolated Persistent Volumes
    volumes:
      - app_data:/app/data

volumes:
  app_data:
    driver: local
```

---

## 3. Directory Layout Standards

Place every project in an isolated directory under `/home/ubuntu/<service-name>/`:

```text
/home/ubuntu/<service-name>/
├── docker-compose.yml     # Compose service manifest
├── Dockerfile             # Multi-stage production container build
├── .env                   # Secret environment variables (never committed to git)
├── .env.example           # Non-sensitive variable documentation
└── data/ (or volumes)     # Local persistent bind mounts if needed
```

---

## 4. Multi-Stage Dockerfile Best Practices

To avoid wasting gigabytes of disk space on build SDKs:
- **Build Stage**: Use full SDK image (`golang`, `mcr.microsoft.com/dotnet/sdk`, `node:alpine`).
- **Runtime Stage**: Copy only compiled artifacts to minimal base image (`alpine`, `distroless`, `mcr.microsoft.com/dotnet/aspnet:alpine`).
- **Clean Cache**: Strip intermediate layers and remove package manager caches (`rm -rf /var/cache/apk/*` or `npm cache clean --force`).

---

## 5. Safe Service Deployment & Hot Update SOP

When deploying an updated version of a service:

```bash
# 1. Navigate to service folder
cd /home/ubuntu/<service-name>

# 2. Pull git changes or stage updated build
git pull origin main

# 3. Rebuild and bring up in background (keeps previous container running until new is ready)
docker compose up -d --build --no-deps <service-name>

# 4. Inspect container health & logs
docker compose logs --tail=40 -f <service-name>
```

---

## 6. Communicating with Dockerized Nginx Gateway

When the Nginx reverse proxy runs in its own Docker container (`nginx-proxy`):
1. **Option A: Host Gateway (Recommended for simple port mappings)**:
   - The application binds its port to host loopback: `- "127.0.0.1:3050:3050"`.
   - Nginx connects via `http://host.docker.internal:3050`.
   - Requires `extra_hosts: - "host.docker.internal:host-gateway"` in `nginx-proxy/docker-compose.yml`.
2. **Option B: Shared Docker Bridge Network**:
   - Create shared bridge: `docker network create gateway-net`.
   - Attach both `nginx-proxy` and target containers to `gateway-net`.
   - Nginx connects directly to container name: `http://app-service:3050`.
