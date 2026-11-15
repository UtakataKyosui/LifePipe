# 外部 API（OpenAPI 仕様）

LifePipe のブラウザ（TanStack Start フロントエンド）と edge（BFF サービス）間の外部 API 契約。
各生活ドメインの要件（[docs/requirements/](requirements/README.md)）を根拠に定義している。

## 概要

- **仕様ファイル**: [`openapi/openapi.yaml`](../openapi/openapi.yaml)
- **仕様バージョン**: OpenAPI 3.0.3（oapi-codegen および Orval の安定動作のため 3.0.x を採用）
- **エンドポイント Base URL**: `/api/v1`
- **認証**: OIDC ID 基盤が発行する Bearer JWT（`bearerAuth`）
- **エラー形式**: RFC 9457 Problem Details（`application/problem+json`）

## ドメインとリソース構成

6つの生活ドメインをすべて単一の統合 OpenAPI 仕様として提供する。

| ドメイン | タグ / パス接頭辞 | 対象領域 | 要件定義書 |
| --- | --- | --- | --- |
| 物品・固定資産 | `inventory` (`/inventory/...`) | 長期保有品、保管場所階層、タグ、添付、資産番号 | [inventory.md](requirements/inventory.md) |
| 衣服・ワードローブ | `wardrobe` (`/wardrobe/...`) | 衣服、着用履歴、洗濯ステータス、コーディネート | [wardrobe.md](requirements/wardrobe.md) |
| 食材・日用品在庫 | `pantry` (`/pantry/...`) | 在庫、賞味期限、消費・廃棄、買い物リスト、レシピ | [pantry.md](requirements/pantry.md) |
| タスク・家事 | `tasks` (`/tasks/...`) | 単発・繰り返しタスク、プロジェクト、家事ルーチン | [tasks.md](requirements/tasks.md) |
| メモ・思考ログ | `notes` (`/notes/...`) | メモ、タグ、添付ファイル、購買ログ | [notes.md](requirements/notes.md) |
| 固定費・サブスク | `subscriptions` (`/subscriptions/...`) | サブスクリプション、更新サイクル、支払履歴、統計 | [subscriptions.md](requirements/subscriptions.md) |

## 共通規約

### ページング
- パラメータ: `#/components/parameters/Page`（既定 1）、`#/components/parameters/PageSize`（既定 50、最大 200）
- メモ一覧（`notes`）は NOT-BR-23 に従い `#/components/parameters/NotesPageSize`（既定 20、最大 100）を使用
- 一覧のレスポンス形式: `{ items: [...], total: integer, page: integer, page_size: integer }`

### エラーレスポンス（RFC 9457 Problem Details）
すべての 4xx / 5xx エラー応答は `#/components/schemas/Problem` を用いて返却する。
- `400 BadRequest`: パラメータ不備、形式不正
- `401 Unauthorized`: 認証トークン欠落・失効
- `404 NotFound`: リソース不在、または権限不足による隠蔽
- `409 Conflict`: 状態の競合（配下リソースが存在する場所の削除など）
- `422 UnprocessableEntity`: 業務ルール制約違反

### 冪等性（Idempotency）
一括登録や購入取り込みなど、重複実行を防ぐ必要がある操作は `Idempotency-Key` ヘッダー（`#/components/parameters/IdempotencyKey`）を受け付ける。

### 拡張属性
各 operation には追跡用の独自拡張フィールドを付与している:
- `x-lifepipe-requirements`: 根拠となるユースケース ID・業務ルール ID の配列（例: `[INV-UC-07, INV-BR-06]`）
- `x-lifepipe-priority`: `mvp` または `later`

## コード生成

### Go サーバー・クライアント（oapi-codegen）
edge サービスの実装およびテストクライアントの生成には `oapi-codegen`（v2）を使用する。

```sh
# 型定義の生成
oapi-codegen -generate "types" -package edge openapi/openapi.yaml > internal/edge/types.gen.go

# net/http サーバーインターフェースの生成
oapi-codegen -generate "std-http" -package edge openapi/openapi.yaml > internal/edge/server.gen.go

# 設定ファイルを使用する場合
oapi-codegen --config openapi/oapi-codegen.yaml openapi/openapi.yaml
```

### TypeScript クライアント（Orval + TanStack Query）
フロントエンド（web）では Orval を使用し、TanStack Query の Hooks / query options および Zod スキーマを生成する。

```sh
# フロントエンド側での生成コマンド（web ディレクトリ内）
pnpm exec orval --config orval.config.ts
```

## 仕様の検証と Lint

```sh
# Redocly による Lint
npx @redocly/cli lint openapi/openapi.yaml

# スクリプトによる断片の再マージ（必要な場合）
ruby scripts/merge-openapi.rb
```
