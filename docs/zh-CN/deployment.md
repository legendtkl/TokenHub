# 部署

Language: [English](../deployment.md) | 简体中文 | [日本語](../ja/deployment.md)

TokenHub 面向私有化部署，由 Go 后端、Next.js 管理后台和 SQLite 持久化组成。

## Docker Compose

创建部署环境变量文件：

```bash
cp deploy/.env.example deploy/.env
```

启动前请编辑 `deploy/.env`：

- `TOKENHUB_ADMIN_TOKEN`：Admin API 启动 Token，请使用至少 32 字节的随机值。
- `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`：仅用于创建初始 `admin` 用户，请设置 12–72 字节的密码。
- `TOKENHUB_SECRET_KEY`：后端密钥，请使用至少 32 字节的随机值并保持稳定。
- `TOKENHUB_PUBLIC_BASE_URL`：展示给用户的后端访问地址。
- `NEXT_PUBLIC_API_BASE_URL`：浏览器管理后台访问后端的地址。
- `TOKENHUB_BACKEND_PORT`：后端宿主机端口，默认 `8080`。
- `TOKENHUB_FRONTEND_PORT`：管理后台宿主机端口，默认 `3000`。

在仓库根目录启动：

```bash
./deploy/install.sh
```

脚本会在构建前校验 Compose 环境变量，不输出敏感值地逐项提示不安全的变量。如果 Compose 失败，且本次创建或重启的后端容器处于已退出、重启中、失效或不健康状态，脚本会打印本次启动产生的最多 100 行后端日志。后端之外的故障不会导出无关的后端日志。

只校验配置，不构建或启动容器：

```bash
./deploy/install.sh --check-only
```

使用其他环境文件时，可执行 `./deploy/install.sh --env-file /path/to/deploy.env`。

### 可选：服务器侧构建加速

项目 Dockerfile 不写死区域性的包镜像源。如果服务器访问 Docker Hub、npm 或 Go Module 源较慢，请优先在部署服务器上配置加速，而不是修改 Dockerfile。

对于基础镜像拉取，可在服务器 Docker daemon 中配置镜像加速，例如 `/etc/docker/daemon.json`，然后重启 Docker：

```json
{
	"registry-mirrors": [
		"https://<your-docker-registry-mirror>"
	]
}
```

对于镜像构建阶段的依赖下载，建议在服务器上为 Docker 或 BuildKit 配置 HTTP/HTTPS 出口代理。这样可以保持构建可移植，避免把特定环境的 npm 或 Go 代理配置提交到仓库。

如果部署环境直接访问上游源较慢，可以参考以下服务器侧配置示例：

```bash
# Go Module 下载
go env -w GOPROXY=https://goproxy.cn,direct

# npm 包下载
npm config set registry https://registry.npmmirror.com
```

这些命令用于配置服务器或构建环境。除非明确维护特定环境的分支，否则不要直接写入项目 Dockerfile。

Compose 会启动：

- 后端：`http://localhost:8080`
- 前端：`http://localhost:3000`
- SQLite 数据：保存在 Docker named volume `tokenhub-data`
- 模型目录：从 `data/model-catalog.yaml` 挂载

查看状态：

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml ps
```

首次登录后台：

- 用户名：`admin`
- 密码：配置的 `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`

在 `prod`、`production`、预发布等非开发环境中，服务会拒绝占位值、少于 32 字节的 Admin Token 或后端密钥，以及少于 12 字节的初始密码。创建初始管理员时，还会拒绝超过 bcrypt 72 字节上限的密码。

手动查看或持续跟踪日志：

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml logs -f
```

停止服务：

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down
```

停止并删除 SQLite 数据卷：

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down -v
```

只有在你明确要删除本地数据时，才使用 `down -v`。

## 后端环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TOKENHUB_ENV` | `prod` | 运行环境标识 |
| `TOKENHUB_HTTP_ADDR` | `:8080` | 后端监听地址 |
| `TOKENHUB_PUBLIC_BASE_URL` | `http://localhost:8080` | 展示给用户的后端地址 |
| `TOKENHUB_TRUSTED_PROXY_CIDRS` | 空 | 允许提供 `X-Forwarded-For` 的代理 IP 或 CIDR，逗号分隔 |
| `TOKENHUB_ADMIN_TOKEN` | `change-me-tokenhub-admin-token` | Admin API 启动访问 Token |
| `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD` | `change-me-tokenhub-admin-password` | 初始 `admin` 用户密码；请使用 12–72 字节并在生产启动前修改 |
| `TOKENHUB_SECRET_KEY` | `change-me-tokenhub-secret-key` | 后端密钥 |
| `TOKENHUB_DATABASE_URL` | `sqlite:///app/data/tokenhub.db` | 容器内 SQLite 数据库路径 |
| `TOKENHUB_SQLITE_BACKUP_DIR` | `/app/data/backups` | 备份目录 |
| `TOKENHUB_MODEL_CATALOG_FILE` | `/app/catalog/model-catalog.yaml` | 标准模型目录文件 |
| `TOKENHUB_SEED_DEMO` | `false` | 是否写入演示数据 |
| `TOKENHUB_LOG_LEVEL` | `info` | 日志级别 |
| `TOKENHUB_RESOURCE_FAILURE_THRESHOLD` | `3` | Provider 资源进入冷却前的失败阈值 |
| `TOKENHUB_RESOURCE_COOLDOWN_SECONDS` | `300` | Provider 资源冷却秒数 |

## 前端环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8080` | 后端 Admin API 地址 |
| `NEXT_PUBLIC_APP_NAME` | `TokenHub` | 页面展示名称 |

## 数据和备份

SQLite 是项目、Key、Provider、路由、用户、请求日志、用量、告警、审批、会话和备份记录的持久化来源。

在一键 compose 部署中：

- 容器内数据库路径：`/app/data/tokenhub.db`
- 容器内备份路径：`/app/data/backups`
- Docker volume 名称：`tokenhub-data`

生产建议：

- 将 SQLite 数据库放在持久化磁盘上。
- 将备份保存到应用容器外部。
- 按保留策略清理旧备份。
- 将 Provider 凭证和 Admin Token 放在密钥管理系统或受保护的环境变量中。

## 模型目录

部署文件会把仓库里的 `data/model-catalog.yaml` 挂载到后端容器的 `/app/catalog/model-catalog.yaml`。

更新标准模型目录：

1. 编辑 `data/model-catalog.yaml`。
2. 重启后端容器。
3. 打开管理后台的 `模型目录` 确认结果。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml restart tokenhub-backend
```

## 反向代理

生产环境建议使用 HTTPS，并转发：

- 管理后台流量到前端服务。
- `/v1/*` 和 `/api/admin/*` 流量到后端服务。

长文本生成和流式响应可能耗时较长，请合理设置请求体大小和超时时间。
