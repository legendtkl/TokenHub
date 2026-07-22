# Deployment

Language: English | [简体中文](zh-CN/deployment.md) | [日本語](ja/deployment.md)

TokenHub is designed for private deployment with a Go backend, a Next.js admin console, and SQLite persistence.

## Docker Compose

Create a deployment environment file:

```bash
cp deploy/.env.example deploy/.env
```

Edit `deploy/.env` before starting:

- `TOKENHUB_ADMIN_TOKEN`: Admin API bootstrap token. Use a random value of at least 32 bytes.
- `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`: Password used only when creating the initial `admin` user. Use 12–72 bytes.
- `TOKENHUB_SECRET_KEY`: Backend secret key. Use a random value of at least 32 bytes and keep it stable.
- `TOKENHUB_PUBLIC_BASE_URL`: Public backend URL shown to users.
- `NEXT_PUBLIC_API_BASE_URL`: Backend URL used by the browser admin console.
- `TOKENHUB_BACKEND_PORT`: Host port for the backend. Default: `8080`.
- `TOKENHUB_FRONTEND_PORT`: Host port for the admin console. Default: `3000`.

Start the stack from the repository root:

```bash
./deploy/install.sh
```

The script validates the Compose environment before building. Validation errors name every unsafe variable without printing its value. If Compose fails and a backend container created or restarted by that attempt is exited, restarting, dead, or unhealthy, the script prints up to 100 backend log lines from that attempt. Failures outside the backend do not export unrelated backend logs.

Validate without building or starting containers:

```bash
./deploy/install.sh --check-only
```

Use a different environment file with `./deploy/install.sh --env-file /path/to/deploy.env`.

### Optional server-side build acceleration

The project Dockerfiles do not hard-code regional package mirrors. If your server has slow access to Docker Hub, npm, or Go module sources, configure acceleration on the deployment host instead of editing Dockerfiles.

For Docker base image pulls, configure Docker daemon registry mirrors on the server, for example in `/etc/docker/daemon.json`, then restart Docker:

```json
{
	"registry-mirrors": [
		"https://<your-docker-registry-mirror>"
	]
}
```

For dependency downloads during image builds, prefer configuring an outbound HTTP/HTTPS proxy for Docker or BuildKit on the server. This keeps builds portable and avoids committing environment-specific npm or Go proxy settings to the repository.

If you deploy in an environment where direct access to upstream registries is slow, the following server-side examples can be used as references:

```bash
# Go module downloads
go env -w GOPROXY=https://goproxy.cn,direct

# npm package downloads
npm config set registry https://registry.npmmirror.com
```

These commands configure the server or build environment. Do not add them directly to project Dockerfiles unless you intentionally maintain an environment-specific fork.

The compose file starts:

- Backend on `http://localhost:8080`
- Frontend on `http://localhost:3000`
- SQLite data stored in the named Docker volume `tokenhub-data`
- Model catalog mounted from `data/model-catalog.yaml`

Check status:

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml ps
```

Initial admin login:

- Username: `admin`
- Password: the configured `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`

For `prod`, `production`, staging, and other non-development environments, startup rejects placeholder values, admin tokens or secret keys shorter than 32 bytes, and bootstrap passwords shorter than 12 bytes. Creating the initial admin also rejects bootstrap passwords longer than bcrypt's 72-byte limit.

View or follow logs manually:

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml logs -f
```

Stop:

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down
```

Stop and remove the SQLite data volume:

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down -v
```

Only use `down -v` when you intentionally want to delete local data.

## Backend Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `TOKENHUB_ENV` | `prod` | Runtime environment label |
| `TOKENHUB_HTTP_ADDR` | `:8080` | Backend listen address |
| `TOKENHUB_PUBLIC_BASE_URL` | `http://localhost:8080` | Public backend URL shown to users |
| `TOKENHUB_TRUSTED_PROXY_CIDRS` | empty | Comma-separated proxy IPs or CIDRs allowed to supply `X-Forwarded-For` |
| `TOKENHUB_ADMIN_TOKEN` | `change-me-tokenhub-admin-token` | Bootstrap admin token for Admin API access |
| `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD` | `change-me-tokenhub-admin-password` | Password for the initial `admin` user; use 12–72 bytes and change it before production startup |
| `TOKENHUB_SECRET_KEY` | `change-me-tokenhub-secret-key` | Backend secret key |
| `TOKENHUB_DATABASE_URL` | `sqlite:///app/data/tokenhub.db` | SQLite database location inside the container |
| `TOKENHUB_SQLITE_BACKUP_DIR` | `/app/data/backups` | Backup output directory |
| `TOKENHUB_MODEL_CATALOG_FILE` | `/app/catalog/model-catalog.yaml` | Standard model catalog file |
| `TOKENHUB_SEED_DEMO` | `false` | Whether to seed demo data |
| `TOKENHUB_LOG_LEVEL` | `info` | Log level |
| `TOKENHUB_RESOURCE_FAILURE_THRESHOLD` | `3` | Provider resource failure threshold before cooldown |
| `TOKENHUB_RESOURCE_COOLDOWN_SECONDS` | `300` | Provider resource cooldown seconds |

## Frontend Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8080` | Backend Admin API URL |
| `NEXT_PUBLIC_APP_NAME` | `TokenHub` | Display name |

## Data and Backups

SQLite is the persistent source for projects, keys, Providers, routes, users, request logs, usage, alerts, approvals, sessions, and backup records.

In the one-command compose deployment:

- Database path inside the backend container: `/app/data/tokenhub.db`
- Backup path inside the backend container: `/app/data/backups`
- Docker volume name: `tokenhub-data`

Recommended production setup:

- Store the SQLite database on a persistent disk.
- Store backups outside the application container.
- Rotate old backups according to your retention policy.
- Keep provider credentials and admin tokens in a secret manager or protected environment variables.

## Model Catalog

The deployment mounts the repository file `data/model-catalog.yaml` into the backend container as `/app/catalog/model-catalog.yaml`.

To update the standard catalog:

1. Edit `data/model-catalog.yaml`.
2. Restart the backend container.
3. Open `Model Catalog` in the admin console and confirm the entries.

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml restart tokenhub-backend
```

## Reverse Proxy

For production, place TokenHub behind HTTPS and forward:

- Admin console traffic to the frontend service.
- `/v1/*` and `/api/admin/*` traffic to the backend service.

Set request body and streaming timeouts high enough for long model responses.
