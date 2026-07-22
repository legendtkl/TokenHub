# デプロイ

Language: [English](../deployment.md) | [简体中文](../zh-CN/deployment.md) | 日本語

TokenHub は、Go バックエンド、Next.js 管理コンソール、SQLite 永続化で構成されるプライベートデプロイ向けのサービスです。

## Docker Compose

デプロイ用の環境変数ファイルを作成します。

```bash
cp deploy/.env.example deploy/.env
```

起動前に `deploy/.env` を編集してください。

- `TOKENHUB_ADMIN_TOKEN`: Admin API の初期 Token。32 バイト以上のランダム値を使用してください。
- `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`: 初期 `admin` ユーザーの作成時にのみ使用するパスワード。12～72 バイトにしてください。
- `TOKENHUB_SECRET_KEY`: バックエンド秘密鍵。32 バイト以上のランダム値を使用し、安定して保持してください。
- `TOKENHUB_PUBLIC_BASE_URL`: ユーザーに表示するバックエンド URL。
- `NEXT_PUBLIC_API_BASE_URL`: ブラウザの管理コンソールが使用するバックエンド URL。
- `TOKENHUB_BACKEND_PORT`: バックエンドのホスト側ポート。デフォルトは `8080`。
- `TOKENHUB_FRONTEND_PORT`: 管理コンソールのホスト側ポート。デフォルトは `3000`。

リポジトリルートから起動します。

```bash
./deploy/install.sh
```

スクリプトはビルド前に Compose の環境変数を検証し、秘密値を表示せずに安全でない変数を個別に報告します。Compose が失敗し、その試行で作成または再起動したバックエンドコンテナが exited、restarting、dead、unhealthy のいずれかである場合、その試行のバックエンドログを最大 100 行表示します。バックエンド以外の障害では、無関係なバックエンドログを出力しません。

コンテナをビルドまたは起動せず、設定だけを検証するには次を実行します。

```bash
./deploy/install.sh --check-only
```

別の環境ファイルを使用する場合は、`./deploy/install.sh --env-file /path/to/deploy.env` を実行します。

### 任意: サーバー側のビルド高速化

このプロジェクトの Dockerfile には、地域依存のパッケージミラーをハードコードしません。サーバーから Docker Hub、npm、Go Module ソースへのアクセスが遅い場合は、Dockerfile を編集せず、デプロイ先サーバー側で高速化を設定してください。

ベースイメージの取得には、サーバーの Docker daemon にレジストリミラーを設定できます。例として `/etc/docker/daemon.json` を編集し、Docker を再起動します。

```json
{
	"registry-mirrors": [
		"https://<your-docker-registry-mirror>"
	]
}
```

イメージビルド中の依存関係ダウンロードについては、サーバーで Docker または BuildKit 向けの HTTP/HTTPS アウトバウンドプロキシを設定することを推奨します。これによりビルドの移植性を保ち、環境固有の npm や Go proxy 設定をリポジトリにコミットせずに済みます。

デプロイ環境から上流レジストリへの直接アクセスが遅い場合は、次のサーバー側設定例を参考にできます。

```bash
# Go Module のダウンロード
go env -w GOPROXY=https://goproxy.cn,direct

# npm パッケージのダウンロード
npm config set registry https://registry.npmmirror.com
```

これらのコマンドはサーバーまたはビルド環境を設定するためのものです。環境固有の fork を意図的に保守する場合を除き、プロジェクトの Dockerfile には直接追加しないでください。

Compose は次を起動します。

- バックエンド: `http://localhost:8080`
- フロントエンド: `http://localhost:3000`
- SQLite データ: Docker named volume `tokenhub-data`
- モデルカタログ: `data/model-catalog.yaml` からマウント

状態を確認します。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml ps
```

初回管理者ログイン:

- ユーザー名: `admin`
- パスワード: 設定した `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD`

`prod`、`production`、ステージングなどの非開発環境では、プレースホルダー値、32 バイト未満の Admin Token または秘密鍵、12 バイト未満の初期パスワードを拒否します。初期管理者の作成時には、bcrypt の上限である 72 バイトを超えるパスワードも拒否します。

ログを手動で確認または追跡します。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml logs -f
```

停止します。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down
```

停止して SQLite データボリュームも削除します。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml down -v
```

`down -v` は、ローカルデータを削除したい場合にのみ使用してください。

## バックエンド環境変数

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `TOKENHUB_ENV` | `prod` | ランタイム環境名 |
| `TOKENHUB_HTTP_ADDR` | `:8080` | バックエンド待受アドレス |
| `TOKENHUB_PUBLIC_BASE_URL` | `http://localhost:8080` | ユーザーに表示するバックエンド URL |
| `TOKENHUB_TRUSTED_PROXY_CIDRS` | 空 | `X-Forwarded-For` を提供できるプロキシ IP または CIDR（カンマ区切り） |
| `TOKENHUB_ADMIN_TOKEN` | `change-me-tokenhub-admin-token` | Admin API 用の初期 Token |
| `TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD` | `change-me-tokenhub-admin-password` | 初期 `admin` ユーザーのパスワード。12～72 バイトを使用し、本番起動前に変更が必要 |
| `TOKENHUB_SECRET_KEY` | `change-me-tokenhub-secret-key` | バックエンド秘密鍵 |
| `TOKENHUB_DATABASE_URL` | `sqlite:///app/data/tokenhub.db` | コンテナ内 SQLite データベースパス |
| `TOKENHUB_SQLITE_BACKUP_DIR` | `/app/data/backups` | バックアップ出力ディレクトリ |
| `TOKENHUB_MODEL_CATALOG_FILE` | `/app/catalog/model-catalog.yaml` | 標準モデルカタログファイル |
| `TOKENHUB_SEED_DEMO` | `false` | デモデータを投入するか |
| `TOKENHUB_LOG_LEVEL` | `info` | ログレベル |
| `TOKENHUB_RESOURCE_FAILURE_THRESHOLD` | `3` | Provider リソースをクールダウンするまでの失敗しきい値 |
| `TOKENHUB_RESOURCE_COOLDOWN_SECONDS` | `300` | Provider リソースのクールダウン秒数 |

## フロントエンド環境変数

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8080` | バックエンド Admin API URL |
| `NEXT_PUBLIC_APP_NAME` | `TokenHub` | 表示名 |

## データとバックアップ

SQLite は、プロジェクト、Key、Provider、ルート、ユーザー、リクエストログ、利用量、アラート、承認、セッション、バックアップ記録の永続化元です。

ワンコマンド compose デプロイでは次を使用します。

- コンテナ内データベースパス: `/app/data/tokenhub.db`
- コンテナ内バックアップパス: `/app/data/backups`
- Docker volume 名: `tokenhub-data`

本番環境の推奨:

- SQLite データベースを永続ディスクに保存します。
- バックアップをアプリケーションコンテナ外に保存します。
- 保持ポリシーに従って古いバックアップを削除します。
- Provider 認証情報と Admin Token はシークレット管理または保護された環境変数で扱います。

## モデルカタログ

デプロイファイルは、リポジトリ内の `data/model-catalog.yaml` をバックエンドコンテナの `/app/catalog/model-catalog.yaml` にマウントします。

標準モデルカタログを更新する手順:

1. `data/model-catalog.yaml` を編集します。
2. バックエンドコンテナを再起動します。
3. 管理コンソールの `Model Catalog` で結果を確認します。

```bash
docker compose --env-file deploy/.env -f deploy/docker-compose.yml restart tokenhub-backend
```

## リバースプロキシ

本番環境では HTTPS の背後に置き、次のように転送してください。

- 管理コンソールのトラフィックはフロントエンドサービスへ。
- `/v1/*` と `/api/admin/*` はバックエンドサービスへ。

長いモデル応答に備えて、リクエストボディサイズとストリーミングタイムアウトを十分に設定してください。
