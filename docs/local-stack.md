# ローカル環境（Docker Compose）の構成

`compose.yaml` が起動するサービスの構成、データの保存先、よくある問題をまとめる。起動手順は [README](../README.md#6-ローカル環境の起動docker-compose) を参照。

## 構成

| コンポーネント | Dockerfile | ビルドコンテキスト | 備考 |
| --- | --- | --- | --- |
| postgres | 公式イメージ | - | `docker/postgres/init-databases.sh` が論理DBとロールを作る |
| redis | 公式イメージ | - | Wardrowbe のジョブキュー（arq）専用 |
| homebox | `docker/homebox/Dockerfile` | `submodules/homebox` | Nuxt をビルドし、Go バイナリに同梱する |
| memos | `docker/memos/Dockerfile` | `submodules/memos` | フロントエンドをビルドしてから Go に埋め込む |
| vikunja | `docker/vikunja/Dockerfile` | `submodules/vikunja` | フロントエンドを埋め込み、静的リンクの Go バイナリを作る |
| grocy | `docker/grocy/Dockerfile` | `submodules/grocy` | upstream に Dockerfile が無いため自作。nginx と php-fpm を1コンテナで動かす |
| wallos | `docker/wallos/Dockerfile` | `submodules/Wallos` | PHP 拡張をビルド用ステージで作り、実行用ステージにコピーする |
| wardrowbe-* | `docker/wardrowbe/Dockerfile.{backend,frontend}` | `submodules/wardrowbe/{backend,frontend}` | `migrate` / `backend` / `worker` / `image-worker` は同じイメージ |

どの Dockerfile もマルチステージで、ビルドに必要なソースだけを `COPY` する。サブモジュールの中身は変更しない。

## データの保存先

| 対象 | 保存先 |
| --- | --- |
| Homebox・Memos・Vikunja・Wardrowbe のデータ | `postgres_data` ボリューム（論理DB: `homebox` / `memos` / `vikunja` / `wardrowbe`） |
| Homebox の添付ファイル | `homebox_data` |
| Memos の添付ファイル | `memos_data` |
| Vikunja の添付ファイル | `vikunja_files` |
| Grocy | `grocy_data`（SQLite と設定ファイル） |
| Wallos | `wallos_db`（SQLite）、`wallos_logos` |
| Wardrowbe の画像 | `wardrowbe_uploads`、`wardrowbe_rembg_models` |
| Wardrowbe のジョブキュー | `redis_data` |

## 秘密情報の扱い

- 秘密情報は `.env` だけに置く。`.env` は `.gitignore` 済みで、リポジトリには `.env.example` だけを含める。
- 必須の値が空のまま `docker compose` を実行すると、変数名を示すエラーで止まる。
- ポートは `127.0.0.1` にだけ公開する。LAN に公開する場合は、リバースプロキシと認証を別途用意する。

## トラブルシュート

### `password authentication failed` で Homebox などが再起動を繰り返す

`docker/postgres/init-databases.sh` は Postgres のデータディレクトリが空のときにだけ実行される。そのため、一度起動した後に `.env` のパスワードを変えると、DB 側のロールのパスワードと食い違う。

- データを残す場合: `.env` を元の値に戻す。
- 初期化してよい場合: `docker compose down -v` でボリュームを削除してから起動し直す。**すべてのデータが消える。**

### ビルド中に Docker が落ちる・固まる

Docker に割り当てるメモリを増やす（6GB 以上を推奨）。それでも足りない場合は、サービスを1つずつビルドする。

```sh
docker compose build homebox
docker compose build memos
```

### Wardrowbe が開けない

`wardrowbe-nginx` は upstream のテンプレートを読み込み、フロントエンドを `frontend:3000` で参照する。`wardrowbe-frontend` にはこの名前のネットワークエイリアスを付けてある。サービス名やエイリアスを変更する場合は合わせて直す。

### Wardrowbe の AI 機能が動かない

既定の接続先はホスト上の Ollama（`http://host.docker.internal:11434/v1`）。Ollama を起動し、`WARDROWBE_AI_VISION_MODEL` と `WARDROWBE_AI_TEXT_MODEL` に指定したモデルを取得しておく。
