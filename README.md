# LifePipe
# Personal Life OS（認知負荷ゼロ化基盤）コンセプトドキュメント

## 1. 背景と目的（Core Philosophy）

日常生活における微小な意思決定（「今日何を着るか」「洗剤の在庫はあるか」「賞味期限が近い食材は何か」「今月どのサブスクが更新されるか」「あのケーブルはどこにしまったか」）は、一つひとつは小さくとも、累積することで人間の認知リソース（ワーキングメモリ）を確実に消費する。

本プロジェクトは、生活のあらゆるドメインを**単一責任のセルフホスト型マイクロサービス群**として外部化し、それらを **Go製の統合MCP（Model Context Protocol）ゲートウェイ** と **ローカルLLM** でオーケストレーションすることで、人間が日常のルーチンにおいて不必要な記憶・検索・推論を行わずに済む状態（Cognitive Load Zero）を実現することを目的とする。

---

## 2. システムアーキテクチャ概要

各ドメインは既存の成熟したOSSをバックエンド（Single Source of Truth）として採用し、それらをDockerの内部ネットワーク上で稼働させる。その上に薄く型安全なGo製MCPサーバー（`life-mcp`）を配置し、LLMエージェントや定時バッチに対して統一されたツールインターフェースを提供する。

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

1. **責務の完全分離（No Overlap）**: データの二重管理を防ぎ、対象物のライフサイクル（長期保有・着用・消費・タスク・思考・固定費・時間軸）に応じて保存先を一意に定める。
2. **ファサードによる推論支援**: 各サービスの単純なCRUDだけでなく、複数APIをGo側で並列集約して文脈化する「複合ツール（Workflow Tools）」をMCPとして公開し、LLMの推論ステップとトークン消費を最小化する。
3. **プライバシー・バイ・デザイン**: 生活データ・位置・購買履歴・予定はすべてセルフホスト環境およびローカルネットワーク内で完結させる。

---

## 3. ドメイン別コンポーネント一覧（リンク集）

| ドメイン | サービス名 | リポジトリ / 公式リンク | ライセンス | 技術スタック | 担う記憶・推論のオフロード領域 |
| --- | --- | --- | --- | --- | --- |
| **固定資産・物品管理** | **Homebox** | [github.com/sysadminsmedia/homebox](https://github.com/sysadminsmedia/homebox) | AGPL-3.0 | Go / Nuxt 3 | ガジェット、工具、家具、重要書類の階層的な保管場所（Location）、保証期限、QRラベル管理 |
| **衣服・ワードローブ** | **Wardrowbe** | [github.com/Anyesh/wardrowbe](https://github.com/Anyesh/wardrowbe) | MIT | Go / Next.js | 手持ちの衣服カタログ、着用履歴、洗濯ステータス、気温・予定に応じたコーディネート抽出 |
| **食材・日用品・献立** | **Grocy** | [github.com/grocy/grocy](https://github.com/grocy/grocy) | MIT | PHP / SQLite | 冷蔵庫の在庫、賞味期限管理、消耗品（洗剤等）の残量監視と買い物リストの自動生成 |
| **タスク・定期家事** | **Vikunja** | [github.com/go-vikunja/vikunja](https://github.com/go-vikunja/vikunja) | AGPL-3.0 | Go / Vue 3 | 単発タスク、完了日を起点に次回期日が算出される定期メンテナンス・家事ルーチン |
| **思考・ログ・メモ** | **Memos** | [github.com/usememos/memos](https://github.com/usememos/memos) | MIT | Go / React | 思いつき、作業ログ、調査メモ、LLMにコンテキストとして与える個人ナレッジの蓄積 |
| **固定費・サブスク** | **Wallos** | [github.com/ellite/Wallos](https://github.com/ellite/Wallos) | GPL-3.0 | PHP / SQLite | サブスクリプション契約一覧、更新サイクル、次回引き落とし日の監視と出費アラート |
| **時間軸・スケジュール** | **Google Calendar** | [developers.google.com/calendar](https://developers.google.com/workspace/calendar/api/guides/overview) | - | REST API (v3) | 外出予定、移動時間、空き時間の把握（他サービスのアクション発火トリガー） |

---

## 4. コアワークフロー（複合MCPツール構想）

統合MCPサーバー（`life-mcp`）には、各サービスの単体操作に加えて以下の高レベルな複合ツールを実装する。

### 4.1 朝の意思決定ゼロ化（`get_morning_briefing`）

* **トリガー**: 毎朝の定時バッチ、または起床時のLLMへの一言（「おはよう」）。
* **処理内容**:
1. **Google Calendar** から当日の予定（在宅か外出か、最初の外出時刻）を取得。
2. 気象APIの気温・降水確率と **Wardrowbe** の着用可能リストを照合し、当日の服装を1パターン確定。
3. **Vikunja** から当日期限のタスク・定期家事を抽出。
4. **Grocy** から賞味期限が3日以内に迫っている食材を抽出。
5. **Wallos** から数日以内に更新・引き落としがある固定費を抽出。


* **出力**: 人間が考える余地を残さない、当日やるべきこと・着るもの・食べるものの確定ブリーフィング。

### 4.2 購買・レシート自動振り分け（`ingest_purchase`）

* **トリガー**: レシート画像・テキスト、または購入報告の入力。
* **処理内容**: LLMが品目を分類し、適切なサービスのAPIへ自動登録する。
* 長期保有品（家電・ケーブル・書籍等） → **Homebox** へ新規アイテム登録
* 衣類・ファッション小物 → **Wardrowbe** へ登録
* 食材・日用消耗品 → **Grocy** の在庫数を加算し、買い物リストから該当項目を消去
* 購買メモ・領収書ログ → **Memos** へ記録



### 4.3 外出前コンテキストチェック（`prepare_outing`）

* **トリガー**: Google Calendar上の外出予定の直前、または外出時の問いかけ。
* **処理内容**: **Grocy** の「不足している買い物リスト」と **Vikunja** の「外出先タスク」を統合し、帰宅ついでに回収すべきミッションを提示する。

---

## 5. 今後の実装ロードマップ

1. **Phase 1（インフラ基盤構築）**: 6サービス（Homebox, Wardrowbe, Grocy, Vikunja, Memos, Wallos）を単一の `docker-compose.yml` に定義し、ローカル環境で一括起動・APIキー発行を行う。
2. **Phase 2（Go MCPゲートウェイ開発）**: `modelcontextprotocol/go-sdk` をベースに `life-mcp` リポジトリを作成し、各サービスのREST APIクライアントとGoogle Calendar連携を実装する。
3. **Phase 3（複合ワークフローと自動化）**: `errgroup` を用いた並列集約ツール（朝のブリーフィング・レシート振り分け）を実装し、ローカルLLMおよび定期通知パイプラインと接続する。
