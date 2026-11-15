# Personal Life OS（認知負荷ゼロ化基盤）

## 1. 背景と目的（Core Philosophy）

日常生活における微小な意思決定（「今日何を着るか」「洗剤の在庫はあるか」「賞味期限が近い食材は何か」「今月どのサブスクが更新されるか」「あのケーブルはどこにしまったか」）は、一つひとつは小さくとも、累積することで人間の認知リソース（ワーキングメモリ）を確実に消費します。

本プロジェクトは、生活のあらゆるドメインを**単一責任のセルフホスト型マイクロサービス群**として外部化し、それらを **Go製の統合MCP（Model Context Protocol）ゲートウェイ** と **ローカルLLM** でオーケストレーションすることで、人間が日常のルーチンにおいて不必要な記憶・検索・推論を行わずに済む状態（Cognitive Load Zero）を実現することを目的とします。

## 2. システムアーキテクチャ概要

各ドメインは既存の成熟したOSSをバックエンド（Single Source of Truth）として採用し、それらをDockerの内部ネットワーク上で稼働させます。その上に薄く型安全なGo製MCPサーバー（`life-mcp`）を配置し、LLMエージェントや定時バッチに対して統一されたツールインターフェースを提供します。

```text
[ LLM Client / Local LLM (Ollama) / 定時バッチ / CLI ]
                        │
                        │  MCP (Streamable HTTP / stdio)
                        ▼
        ┌───────────────────────────────┐
        │     life-mcp (Go Gateway)     │  ← golang.org/x/sync/errgroup による並列集約
        └─┬───┬───┬───┬───┬───┬───────┬─┘
          │   │   │   │   │   │       │  (REST / gRPC API)
          ▼   ▼   ▼   ▼   ▼   ▼       ▼
      ┌───┴───┴───┴───┴───┴───┴───────┴───┐
      │  Docker Internal Network          │
      │  ・Homebox       ・Vikunja        │
      │  ・Wardrowbe     ・Memos          │
      │  ・Grocy         ・Wallos         │
      └───────────────────────────────────┘
                        │
                        ▼
               [ Google Calendar ]
```

### 設計原則

1. **責務の完全分離（No Overlap）**: データの二重管理を防ぎ、対象物のライフサイクル（長期保有・着用・消費・タスク・思考・固定費・時間軸）に応じて保存先を一意に定めます。
2. **ファサードによる推論支援**: 各サービスの単純なCRUDだけでなく、複数APIをGo側で並列集約して文脈化する「複合ツール（Workflow Tools）」をMCPとして公開し、LLMの推論ステップとトークン消費を最小化します。
3. **プライバシー・バイ・デザイン**: 生活データ・位置・購買履歴・予定はすべてセルフホスト環境およびローカルネットワーク内で完結させます。

## 3. ドメイン別コンポーネント一覧

| ドメイン | サービス名 | リポジトリ / 公式リンク | ライセンス | 技術スタック | 担う記憶・推論のオフロード領域 |
| --- | --- | --- | --- | --- | --- |
| **固定資産・物品管理** | **Homebox** | [github.com/sysadminsmedia/homebox](https://github.com/sysadminsmedia/homebox) | AGPL-3.0 | Go / Nuxt 3 | ガジェット、工具、家具、重要書類の階層的な保管場所（Location）、保証期限、QRラベル管理 |
| **衣服・ワードローブ** | **Wardrowbe** | [github.com/Anyesh/wardrowbe](https://github.com/Anyesh/wardrowbe) | MIT | Go / Next.js | 手持ちの衣服カタログ、着用履歴、洗濯ステータス、気温・予定に応じたコーディネート抽出 |
| **食材・日用品・献立** | **Grocy** | [github.com/grocy/grocy](https://github.com/grocy/grocy) | MIT | PHP / SQLite | 冷蔵庫の在庫、賞味期限管理、消耗品（洗剤等）の残量監視と買い物リストの自動生成 |
| **タスク・定期家事** | **Vikunja** | [github.com/go-vikunja/vikunja](https://github.com/go-vikunja/vikunja) | AGPL-3.0 | Go / Vue 3 | 単発タスク、完了日を起点に次回期日が算出される定期メンテナンス・家事ルーチン |
| **思考・ログ・メモ** | **Memos** | [github.com/usememos/memos](https://github.com/usememos/memos) | MIT | Go / React | 思いつき、作業ログ、調査メモ、LLMにコンテキストとして与える個人ナレッジの蓄積 |
| **固定費・サブスク** | **Wallos** | [github.com/ellite/Wallos](https://github.com/ellite/Wallos) | GPL-3.0 | PHP / SQLite | サブスクリプション契約一覧、更新サイクル、次回引き落とし日の監視と出費アラート |
| **時間軸・スケジュール** | **Google Calendar** | [Google Calendar API](https://developers.google.com/workspace/calendar/api/guides/overview) | - | REST API (v3) | 外出予定、移動時間、空き時間の把握（他サービスのアクション発火トリガー） |

## 4. コアワークフロー（複合MCPツール構想）

統合MCPサーバー（`life-mcp`）には、各サービスの単体操作に加えて以下の高レベルな複合ツールを実装します。

### 4.1 朝の意思決定ゼロ化（`get_morning_briefing`）

**トリガー**: 毎朝の定時バッチ、または起床時のLLMへの一言（「おはよう」）。

**処理内容**:

1. **Google Calendar** から当日の予定（在宅か外出か、最初の外出時刻）を取得。
2. 気象APIの気温・降水確率と **Wardrowbe** の着用可能リストを照合し、当日の服装を1パターン確定。
3. **Vikunja** から当日期限のタスク・定期家事を抽出。
4. **Grocy** から賞味期限が3日以内に迫っている食材を抽出。
5. **Wallos** から数日以内に更新・引き落としがある固定費を抽出。

**出力**: 人間が考える余地を残さない、当日やるべきこと・着るもの・食べるものの確定ブリーフィング。

### 4.2 購買・レシート自動振り分け（`ingest_purchase`）

**トリガー**: レシート画像・テキスト、または購入報告の入力。

**処理内容**: LLMが品目を分類し、適切なサービスのAPIへ自動登録します。

- 長期保有品（家電・ケーブル・書籍等） → **Homebox** へ新規アイテム登録
- 衣類・ファッション小物 → **Wardrowbe** へ登録
- 食材・日用消耗品 → **Grocy** の在庫数を加算し、買い物リストから該当項目を消去
- 購買メモ・領収書ログ → **Memos** へ記録

### 4.3 外出前コンテキストチェック（`prepare_outing`）

**トリガー**: Google Calendar上の外出予定の直前、または外出時の問いかけ。

**処理内容**: **Grocy** の「不足している買い物リスト」と **Vikunja** の「外出先タスク」を統合し、帰宅ついでに回収すべきミッションを提示します。

## 5. 今後の実装ロードマップ

1. **Phase 1（インフラ基盤構築）**: 6サービス（Homebox, Wardrowbe, Grocy, Vikunja, Memos, Wallos）を単一の `compose.yaml` に定義し、ローカル環境で一括起動・APIキー発行を行います。
2. **Phase 2（Go MCPゲートウェイ開発）**: 本リポジトリの `life-mcp` を `modelcontextprotocol/go-sdk` で拡張し、各サービスのREST APIクライアントとGoogle Calendar連携を実装します。
3. **Phase 3（複合ワークフローと自動化）**: `errgroup` を用いた並列集約ツール（朝のブリーフィング・レシート振り分け）を実装し、ローカルLLMおよび定期通知パイプラインと接続します。

## 6. ローカル環境の起動（Docker Compose）

6つのセルフホストサービス（Homebox・Wardrowbe・Grocy・Vikunja・Memos・Wallos）と、Wardrowbe 用の Redis を `compose.yaml` で一括起動します。Google Calendar は外部 API のため含みません。

### 前提

- Docker Engine 25 以上と Docker Compose v2（Wallos のヘルスチェックが `--start-interval` を使うため）
- Docker に割り当てるメモリは 4GB 以上（6GB 以上を推奨。Node・Go のビルドが重いため）
- サブモジュールの取得: `git submodule update --init --recursive`

### 起動手順

```sh
cp .env.example .env
# .env の空欄に秘密情報を入れる（hex の生成例: openssl rand -hex 24）
docker compose build          # 初回のみ。メモリが足りない場合は `docker compose build <サービス名>` を1つずつ実行する
docker compose up -d --wait
```

`.env` は Git に含まれません。パスワードは DSN に埋め込まれるため英数字（hex）にしてください。

### アクセス先

すべて `127.0.0.1` にだけ公開します。ポートは `.env` で変更できます。

| サービス | URL | 保存先 |
| --- | --- | --- |
| Homebox | http://localhost:3100 | 共有 Postgres（`homebox`） |
| Wardrowbe | http://localhost:8080 | 共有 Postgres（`wardrowbe`） |
| Vikunja | http://localhost:3456 | 共有 Postgres（`vikunja`） |
| Memos | http://localhost:5230 | 共有 Postgres（`memos`） |
| Grocy | http://localhost:8081 | SQLite（`grocy_data` ボリューム） |
| Wallos | http://localhost:8282 | SQLite（`wallos_db` ボリューム） |

Database は Postgres 1インスタンスにまとめ、サービスごとに論理DBとロールを分けています。Grocy と Wallos は SQLite 専用のため Postgres には載せられません。

### 初期設定と認証情報

| サービス | 初回ログイン |
| --- | --- |
| Homebox | 画面から最初のユーザーを登録する |
| Vikunja | 画面から最初のユーザーを登録する |
| Memos | 最初に作成したアカウントが管理者になる |
| Wallos | 最初に登録したユーザーが管理者になる |
| Grocy | 既定の `admin` / `admin` でログインし、**すぐにパスワードを変更する** |
| Wardrowbe | `WARDROWBE_DEBUG=true` の間は開発用ログインを使う。外部に公開する場合は OIDC を設定して `false` にする |

Wardrowbe の AI 連携は、既定ではホスト上の Ollama（`http://host.docker.internal:11434/v1`）を指します。接続先は `.env` の `WARDROWBE_AI_*` で変更できます。

### 動作確認

```sh
docker compose ps                                        # すべて healthy / Up（wardrowbe-migrate は Exited (0) が正常）
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3100/api/v1/status   # Homebox: 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3456/api/v1/info     # Vikunja: 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5230/healthz         # Memos: 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/login           # Grocy: 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8282/health.php      # Wallos: 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/api/v1/health   # Wardrowbe: 200
```

データの永続化は、各サービスでデータを作成してから `docker compose down`（`-v` を付けない）→ `docker compose up -d --wait` を実行し、データが残っていることで確認できます。`docker compose down -v` はボリュームを削除するため、データがすべて消えます。

構成の詳細と困ったときの対処は [docs/local-stack.md](docs/local-stack.md) を参照してください。

## Development

The Go MCP gateway scaffold uses Go 1.25 and the official
[`modelcontextprotocol/go-sdk`](https://github.com/modelcontextprotocol/go-sdk).
Start its stdio server with:

```sh
go run ./cmd/life-mcp
```

Run the same checks as CI before submitting changes:

```sh
gofmt -w ./cmd
go test ./...
go vet ./...
```

Repository-specific Go agent guidance is in
`.agents/skills/lifepipe-go/SKILL.md`.

### Go Agent Skills

This repository includes the three upstream [Facta-Dev/beautifulgo](https://github.com/Facta-Dev/beautifulgo) Agent Skills for GitHub Copilot:

- `go-best-practices` — Go implementation guidance
- `go-review` — Go code review guidance
- `go-port` — guidance for porting code to Go

They are installed in `.agents/skills/` and tracked by `skills-lock.json`. To install
or refresh them with the upstream skills installer:

```sh
npx skills add Facta-Dev/beautifulgo -a github-copilot
npx skills update
```

The upstream skills and this project’s `lifepipe-go` skill serve different purposes:
BeautifulGo provides general Go guidance, while `lifepipe-go` records LifePipe-specific
architecture and security requirements. BeautifulGo also describes a particular backend
stack; apply those stack-specific rules only if LifePipe adopts that architecture.
BeautifulGo is MIT-licensed; see [`LICENSES/Facta-Dev-beautifulgo-MIT.txt`](LICENSES/Facta-Dev-beautifulgo-MIT.txt).

### AI coding agents

Shared repository guidance is in [`AGENTS.md`](AGENTS.md). GitHub Copilot also uses
[`.github/copilot-instructions.md`](.github/copilot-instructions.md), while Claude Code
imports the shared guidance through [`CLAUDE.md`](CLAUDE.md). Project-level Codex
configuration is in [`.codex/config.toml`](.codex/config.toml).

Claude Code and Codex have optional project `PostToolUse` hooks that run `gofmt` on
edited Go files. They do not run tests or access the network. See the
[agent setup guide](docs/agent-setup.md) for hook behavior, trust requirements,
troubleshooting, and opt-out instructions.
