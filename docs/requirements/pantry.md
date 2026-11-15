# pantry: 食材・日用品の在庫管理 の要件

参考元: Grocy（MIT）。ソースコードは参照していない。

## 責務

pantry は、家庭で消費する食材と日用品（洗剤・トイレットペーパーなどの消耗品）の在庫を記録するサービスである。

持つデータ:

- 商品のマスタ（名前、数量単位、既定の保管場所、最低在庫数、期限の種類と既定日数）
- 数量単位と単位の換算
- 保管場所（冷蔵庫・冷凍庫・パントリーなど）
- 在庫エントリ（購入ごと・期限ごとの在庫の塊）と、在庫の増減の履歴
- 買い物リストと、その項目

持たないデータと境界:

- 長期保有品（家電・家具など、消費しないもの）は inventory ドメインが持つ。
- 衣類は wardrobe ドメインが持つ。
- 家事・定期作業・タスクは tasks ドメインが持つ。外出先でやること（「ドラッグストアに寄る」など）も tasks の担当で、pantry は買い物リストだけを返す。
- 固定費・サブスクリプションの支払いは pantry の責務ではない。購入価格は在庫エントリの任意項目として記録するだけで、支出の集計は行わない。
- レシピ・献立は扱わない（「対象外」を参照）。
- レシートの解析（画像・テキストから品目を取り出す処理）は LifePipe のワークフロー側で行い、pantry は品目単位の購入登録を受け取る。

## 参考元の構成

- 主な機能のまとまり: 在庫（購入・消費・開封・移動・棚卸し・在庫エントリの編集・履歴）、買い物リスト（複数リスト、最低在庫からの自動追加、リストから在庫への登録）、レシピ、献立、家事、タスク、バッテリー、家庭用機器、カレンダー、利用者定義の項目・オブジェクト。機能ごとにフィーチャーフラグで無効化できる。（出典: submodules/grocy/README.md、https://grocy.info/ ）
- データの保存先: 単一の SQLite データベースと、`data` ディレクトリ内のファイル（商品画像など）。スキーマの移行はアプリ起動時に自動で行う。（出典: submodules/grocy/README.md）
- 外部依存: ジョブキューや AI は持たない。バーコードから商品情報を引く外部サービス（Open Food Facts）をプラグインで呼び出す。ラベル印刷・レシート用サーマルプリンタへの出力を任意で使う。（出典: submodules/grocy/README.md、submodules/grocy/changelog/77_4.4.0_2025-01-24.md、submodules/grocy/changelog/62_3.1.0_2021-07-16.md）
- API: Web 画面と同じ機能を REST API で提供する。（出典: submodules/grocy/README.md）
- 認証方式: ユーザー名とパスワードによるログイン、API キー（ヘッダーまたはクエリパラメータ）、LDAP、リバースプロキシのヘッダーによる認証を選べる。（出典: submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/61_3.0.1_2021-01-05.md）
- マルチユーザーの単位: 1 インストールが 1 世帯で、全利用者が同じデータを共有する。利用者ごとに権限を設定でき、在庫の変更には操作した利用者が記録される。（出典: submodules/grocy/changelog/60_3.0.0_2020-12-22.md）

## エンティティ

LifePipe の pantry も 1 世帯を単位とし、全利用者が同じデータを共有する。日時は ISO 8601（タイムゾーン付き）、日付は `YYYY-MM-DD` で扱う。

### Product（商品）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 商品 ID |
| name | string | 必須 | 商品名。世帯内で一意（PAN-BR-01） |
| description | string | 任意 | 説明 |
| product_group_id | 参照(ProductGroup) | 任意 | 商品グループ |
| default_location_id | 参照(Location) | 必須 | 既定の保管場所。購入時に保管場所を省略するとここに入る |
| default_consume_location_id | 参照(Location) | 任意 | 消費時に優先する保管場所（PAN-BR-11） |
| stock_quantity_unit_id | 参照(QuantityUnit) | 必須 | 在庫数量の基準単位。在庫数量はすべてこの単位で保存する |
| purchase_quantity_unit_id | 参照(QuantityUnit) | 必須 | 購入時と買い物リスト追加時の既定単位。作成時に省略すると在庫単位を設定する |
| consume_quantity_unit_id | 参照(QuantityUnit) | 必須 | 消費時の既定単位。作成時に省略すると在庫単位を設定する |
| min_stock_amount | number | 必須 | 最低在庫数（在庫単位）。0 は「最低在庫を管理しない」。既定 0 |
| due_date_type | enum(best_before, expiration) | 必須 | 期限の種類。既定 best_before（PAN-BR-04） |
| default_due_days | integer | 任意 | 購入日から期限までの既定日数。-1 は期限なし。未設定なら購入時に期限の入力が必要 |
| default_due_days_after_open | integer | 任意 | 開封後の期限日数（PAN-BR-14） |
| default_due_days_after_freezing | integer | 任意 | 冷凍庫へ移したときの期限日数。-1 は期限なし（後回し） |
| default_due_days_after_thawing | integer | 任意 | 冷凍庫から出したときの期限日数（後回し） |
| treat_opened_as_out_of_stock | boolean | 必須 | 開封済みの在庫を最低在庫の判定で「在庫なし」と数えるか。既定 true（PAN-BR-19） |
| can_be_opened | boolean | 必須 | 開封の記録を許すか。既定 true |
| quick_consume_amount | number | 必須 | ワンタップ消費の数量（消費単位）。既定 1 |
| active | boolean | 必須 | false の商品は一覧・自動追加の対象から外す。履歴は残す（PAN-BR-03） |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### ProductGroup（商品グループ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 商品グループ ID |
| name | string | 必須 | グループ名（例: 野菜、乳製品、日用品）。一意 |
| sort_order | integer | 任意 | 買い物リストでの並び順（売り場順に並べる用途） |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### QuantityUnit（数量単位）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 数量単位 ID |
| name | string | 必須 | 単位名（例: 個、パック、g、ml）。一意 |
| name_plural | string | 任意 | 複数形の表示名。未設定なら name を使う |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### QuantityUnitConversion（数量単位の換算）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 換算 ID |
| from_quantity_unit_id | 参照(QuantityUnit) | 必須 | 換算元の単位 |
| to_quantity_unit_id | 参照(QuantityUnit) | 必須 | 換算先の単位 |
| factor | number | 必須 | 換算元 1 単位が換算先の何単位か。0 より大きい |
| product_id | 参照(Product) | 任意 | 指定すると、その商品だけに効く換算になる。未指定なら全商品共通 |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### Location（保管場所）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 保管場所 ID |
| name | string | 必須 | 場所名（例: 冷蔵庫、冷凍庫、パントリー）。一意 |
| description | string | 任意 | 説明 |
| is_freezer | boolean | 必須 | 冷凍庫か。既定 false（PAN-BR-23） |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### StockEntry（在庫エントリ）

購入 1 回（または期限・保管場所・開封状態が同じ在庫の塊）を表す。商品の在庫数量は、その商品の在庫エントリの数量の合計である。

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 在庫エントリ ID |
| product_id | 参照(Product) | 必須 | 商品 |
| location_id | 参照(Location) | 必須 | 保管場所 |
| amount | number | 必須 | 残数量（在庫単位）。0 より大きい。0 になったエントリは削除する |
| due_date | date | 任意 | 期限日。null は期限なし（PAN-BR-05） |
| purchased_date | date | 必須 | 購入日。既定は登録日 |
| opened | boolean | 必須 | 開封済みか |
| opened_date | date | 任意 | 開封日。opened が true のとき必須 |
| unit_price | number | 任意 | 在庫単位あたりの購入価格 |
| note | string | 任意 | メモ（同じ商品の銘柄違いの区別など） |
| created_at | date-time | 必須 | 作成日時。消費順の先入れ先出しの基準（PAN-BR-11） |
| updated_at | date-time | 必須 | 更新日時 |

### StockTransaction（在庫の増減の履歴）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 履歴 ID |
| correlation_id | string | 必須 | 1 回の操作で作られた履歴をまとめる ID（1 回の消費が複数の在庫エントリにまたがる場合など） |
| type | enum(purchase, consume, open, transfer_from, transfer_to, inventory_correction, stock_edit) | 必須 | 増減の種類 |
| product_id | 参照(Product) | 必須 | 商品 |
| stock_entry_id | 参照(StockEntry) | 必須 | 対象の在庫エントリ（削除済みでも ID は残す） |
| location_id | 参照(Location) | 必須 | 操作時の保管場所 |
| amount | number | 必須 | 増減量（在庫単位）。増加は正、減少は負 |
| spoiled | boolean | 必須 | 廃棄による消費か。type が consume のときだけ true になりうる |
| due_date | date | 任意 | 操作時点の在庫エントリの期限日 |
| unit_price | number | 任意 | 購入時の単価 |
| source | enum(manual, shopping_list, ingest_purchase, auto) | 必須 | 操作の経路 |
| user_id | string | 必須 | 操作した利用者 |
| undone | boolean | 必須 | 取り消し済みか（後回し） |
| undone_at | date-time | 任意 | 取り消し日時（後回し） |
| created_at | date-time | 必須 | 作成日時 |

### ShoppingList（買い物リスト）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 買い物リスト ID |
| name | string | 必須 | リスト名。一意 |
| is_default | boolean | 必須 | 既定のリストか。世帯に 1 つだけ true（PAN-BR-26） |
| note | string | 任意 | リスト全体のメモ |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### ShoppingListItem（買い物リストの項目）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 項目 ID |
| shopping_list_id | 参照(ShoppingList) | 必須 | 所属するリスト |
| product_id | 参照(Product) | 任意 | 商品。未指定なら自由記述の項目（PAN-BR-27） |
| note | string | 任意 | 自由記述。product_id が未指定のとき必須 |
| amount | number | 必須 | 数量。0 より大きい |
| quantity_unit_id | 参照(QuantityUnit) | 任意 | 数量の単位。product_id があるときは必須で、その商品で換算できる単位に限る |
| done | boolean | 必須 | 購入済み（消し込み済み）か。既定 false |
| done_at | date-time | 任意 | 消し込み日時 |
| origin | enum(manual, below_min_stock, overdue, expired) | 必須 | 追加された理由 |
| created_at | date-time | 必須 | 作成日時 |
| updated_at | date-time | 必須 | 更新日時 |

### PantrySettings（世帯の在庫設定）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| due_soon_days | integer | 必須 | 「期限が近い」とみなす日数。既定 3（PAN-BR-07） |
| auto_add_below_min_stock | boolean | 必須 | 最低在庫を下回ったとき既定の買い物リストへ自動追加するか。既定 false（PAN-BR-20） |
| updated_at | date-time | 必須 | 更新日時 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| PAN-UC-01 | 商品を登録・更新・無効化・削除する（名前、数量単位、既定の保管場所、最低在庫数、期限の種類と既定日数） | MVP | https://grocy.info/ 、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-02 | 商品を一覧・検索する（フィルタ: 名前、保管場所、商品グループ、在庫あり/なし、有効/無効） | MVP | submodules/grocy/changelog/62_3.1.0_2021-07-16.md、submodules/grocy/changelog/70_4.0.0_2023-07-29.md |
| PAN-UC-03 | 数量単位を登録・更新・削除する | MVP | submodules/grocy/changelog/52_2.5.0_2019-09-22.md |
| PAN-UC-04 | 数量単位の換算（全商品共通、商品ごと）を登録・更新・削除する | MVP | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/70_4.0.0_2023-07-29.md |
| PAN-UC-05 | 保管場所を登録・更新・削除する | MVP | submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-UC-06 | 購入した商品を在庫に加える（数量・単位・期限日・保管場所・購入日・価格） | MVP | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-07 | 商品を消費する（数量・単位、保管場所の指定、在庫エントリの指定） | MVP | submodules/grocy/changelog/39_1.23.0_2018-11-24.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-08 | 商品を開封済みにする | MVP | submodules/grocy/changelog/39_1.23.0_2018-11-24.md、submodules/grocy/changelog/62_3.1.0_2021-07-16.md |
| PAN-UC-09 | 商品を廃棄する（廃棄フラグ付きの消費） | MVP | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/74_4.1.0_2024-02-09.md |
| PAN-UC-10 | 商品ごとの在庫数量と、期限日・保管場所・開封状態ごとの在庫エントリを取得する | MVP | submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-UC-11 | 期限が近い・期限切れ（best before 超過 / expiration 超過）の在庫を取得する | MVP | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、https://grocy.info/ |
| PAN-UC-12 | 最低在庫を下回った商品と不足量を取得する | MVP | submodules/grocy/changelog/7_1.1.0_2017-04-21.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-UC-13 | 最低在庫を下回った商品を買い物リストに追加する（手動実行と、設定による自動追加） | MVP | submodules/grocy/changelog/7_1.1.0_2017-04-21.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-UC-14 | 買い物リストの項目を追加・更新・削除する（商品または自由記述） | MVP | submodules/grocy/changelog/14_1.7.0_2018-04-15.md、submodules/grocy/changelog/52_2.5.0_2019-09-22.md |
| PAN-UC-15 | 買い物リストの項目を購入済みにして在庫へ加える（消し込み） | MVP | submodules/grocy/changelog/39_1.23.0_2018-11-24.md |
| PAN-UC-16 | 購入報告（複数品目）をまとめて在庫に加え、対応する買い物リストの項目を消し込む | MVP | README.md（§4.2 ingest_purchase）、submodules/grocy/changelog/39_1.23.0_2018-11-24.md |
| PAN-UC-17 | 購入済みの項目をリストから一括削除する | MVP | submodules/grocy/changelog/70_4.0.0_2023-07-29.md、submodules/grocy/changelog/66_3.2.0_2022-02-11.md |
| PAN-UC-18 | 在庫の増減の履歴を取得する（フィルタ: 商品、種類、期間、利用者） | MVP | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-19 | 世帯の在庫設定（期限が近いとみなす日数、自動追加の有無）を取得・更新する | MVP | submodules/grocy/changelog/67_3.3.0_2022-04-08.md、submodules/grocy/changelog/81_4.6.0_2026-03-06.md |
| PAN-UC-20 | 棚卸し: 実数を入力して在庫数量を補正する | 後回し | submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-UC-21 | 保管場所間で在庫を移動する（冷凍・解凍に伴う期限の変更を含む） | 後回し | submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-UC-22 | 在庫エントリを直接編集する（期限日・保管場所・数量・メモ） | 後回し | submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-UC-23 | 在庫の増減を取り消す | 後回し | submodules/grocy/changelog/38_1.22.0_2018-10-27.md、submodules/grocy/changelog/52_2.5.0_2019-09-22.md |
| PAN-UC-24 | 期限切れ（best before 超過・expiration 超過）の在庫を買い物リストに追加する | 後回し | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-25 | 複数の買い物リストを作成・名前変更・削除する | 後回し | submodules/grocy/changelog/47_2.4.0_2019-05-10.md、submodules/grocy/changelog/65_3.1.3_2021-11-14.md |
| PAN-UC-26 | 商品グループを管理し、買い物リストをグループ順に並べる | 後回し | submodules/grocy/changelog/33_1.19.0_2018-09-24.md、https://grocy.info/ |
| PAN-UC-27 | バーコードで商品を特定し、購入数量・単位を自動入力する | 後回し | submodules/grocy/README.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-UC-28 | 2 つの商品を統合する（履歴・在庫・リスト項目を片方へ寄せる） | 後回し | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |

## 業務ルール

| ID | ルール | 出典 |
| --- | --- | --- |
| PAN-BR-01 | 商品名・数量単位名・保管場所名・買い物リスト名・商品グループ名は、それぞれ世帯内で一意とする。重複する名前での登録・更新は 409 で拒否する。比較は大文字小文字と前後の空白を区別しない。 | submodules/grocy/changelog/82_4.7.0_2026-08-28.md |
| PAN-BR-02 | 在庫数量・最低在庫数・買い物リストの数量は小数を許す。保存精度は小数第 4 位までとする。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-03 | 在庫エントリまたは履歴を持つ商品は、削除する前に無効化（active=false）を推奨する。無効な商品は商品一覧（既定のフィルタ）、期限の近い在庫、最低在庫の判定、自動追加の対象外とする。削除した場合は、その商品の在庫エントリ・履歴・買い物リスト項目・商品ごとの換算もあわせて削除する。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/63_3.1.1_2021-08-21.md |
| PAN-BR-04 | 期限の種類: `best_before`（賞味期限）は「おいしく食べられる目安」で、期限日を過ぎた在庫は「期限超過（overdue）」と呼び、引き続き消費できる。`expiration`（消費期限）は「安全に食べられる期限」で、期限日を過ぎた在庫は「期限切れ（expired）」と呼び、廃棄の候補として扱う。種類は商品単位で持ち、その商品のすべての在庫エントリに適用する。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-05 | 期限なし: 在庫エントリの due_date が null のとき「期限なし」とし、期限の判定・期限の近い在庫の取得の対象外とする。商品の default_due_days が -1 なら、購入時の期限日を null にする。参考元は期限なしを 2999-12-31 という固定日付で表すが、LifePipe では null で表す。 | submodules/grocy/README.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-06 | 購入時の期限日の決め方: リクエストに期限日があればそれを使う。なければ、商品の default_due_days が 0 以上なら「購入日 + default_due_days 日」、-1 なら null、未設定ならリクエストを 422 で拒否する。購入先の保管場所が冷凍庫で、商品に default_due_days_after_freezing が設定されているときは、そちらを優先する（冷凍は後回しの機能だが、日数の項目は MVP で受け付ける）。今日以前の期限日も受け付け、レスポンスに警告を付ける。 | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/45_2.2.0_2019-03-10.md、submodules/grocy/changelog/65_3.1.3_2021-11-14.md |
| PAN-BR-07 | 期限の状態の判定。基準日を今日（世帯のタイムゾーンの日付）とし、`残り日数 = due_date - 今日` とする。`残り日数 < 0` なら、best_before は overdue、expiration は expired。`0 ≤ 残り日数 ≤ due_soon_days` なら due_soon（今日が期限日のものを含む）。それ以外は ok。due_soon_days の既定は 3 で、0 以上の整数に限る。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/74_4.1.0_2024-02-09.md、README.md（§4.1 get_morning_briefing） |
| PAN-BR-08 | 期限の近い在庫の取得は、在庫エントリ単位で返し、期限日の昇順に並べる。フィルタとして `within_days`（既定は due_soon_days）と状態（due_soon / overdue / expired）を受け付ける。商品単位の要約では、その商品の在庫エントリのうち最も早い期限日を「次の期限日」とする。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/62_3.1.0_2021-07-16.md |
| PAN-BR-09 | 数量単位の換算: 換算は「from 1 単位 = to の factor 単位」で定義する。換算を 1 件登録すると逆向き（factor の逆数）の換算を自動で作成・更新・削除する。同じ単位どうし（from = to）の換算は登録できない。factor は 0 より大きい。同じ from・to・product_id の組は一意。 | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-BR-10 | 換算の解決: 商品 P について単位 A から B へ換算するとき、(1) P 専用の換算、(2) 全商品共通の換算、の順で直接の換算を探す。直接の換算がなければ、換算を辺とするグラフをたどって間接的に求め（例: 小さじ → ml → l）、経路上の factor を掛け合わせる。経路の探索でも P 専用の換算を共通の換算より優先する。経路がなければ、その単位はその商品では使えず、リクエストを 422 で拒否する。在庫数量は常に在庫単位へ換算して保存する（例: 在庫単位が「個」、購入単位が「パック」、P 専用の換算「1 パック = 6 個」のとき、2 パックの購入は在庫 12 個）。 | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/70_4.0.0_2023-07-29.md |
| PAN-BR-11 | 消費の順序: 在庫エントリを指定しない消費・開封・廃棄では、次の順で在庫エントリを選ぶ。(1) 保管場所が指定されていればその場所の在庫だけを対象にする。指定がなく商品に default_consume_location_id があれば、その場所の在庫を先に使う。(2) 開封済みのエントリを先にする。(3) 期限日が早いものを先にする（期限なしは最後）。(4) 期限日が同じなら購入日、次に created_at が古いもの（先入れ先出し）を先にする。開封の操作では (2) を適用せず、未開封のエントリだけを対象にする。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-BR-12 | 消費量が 1 つの在庫エントリより多い場合は、PAN-BR-11 の順に複数のエントリから引き、エントリごとに履歴を作り、同じ correlation_id でまとめる。在庫エントリの数量が 0 になったらエントリを削除する。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-13 | 在庫不足の扱い: 消費・開封・廃棄の数量が対象の在庫の合計より多い場合は、何も変更せず 422 で拒否する（一部だけ消費しない）。 | submodules/grocy/changelog/69_3.3.2_2022-11-12.md、submodules/grocy/changelog/76_4.3.0_2024-12-23.md |
| PAN-BR-14 | 開封: 開封数量が在庫エントリの数量より少ないときは、エントリを開封済みのエントリと未開封のエントリに分ける（購入日・価格・メモは引き継ぐ）。開封したエントリの opened を true、opened_date を今日にする。商品に default_due_days_after_open があれば、新しい期限日を `min(元の期限日, 今日 + default_due_days_after_open)` とする（元の期限より延ばさない。元が期限なしなら今日 + 日数）。can_be_opened が false の商品の開封は 422 で拒否する。 | submodules/grocy/changelog/39_1.23.0_2018-11-24.md、submodules/grocy/changelog/62_3.1.0_2021-07-16.md、submodules/grocy/changelog/77_4.4.0_2025-01-24.md |
| PAN-BR-15 | 廃棄は消費の一種として扱い、履歴の type を consume、spoiled を true にする。在庫の減らし方は消費と同じ（PAN-BR-11〜13）。廃棄の件数・数量は履歴から集計できるようにする。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/62_3.1.0_2021-07-16.md |
| PAN-BR-16 | 購入: 購入 1 件ごとに在庫エントリを 1 つ作る（既存のエントリと合算しない）。保管場所の指定がなければ商品の default_location_id を使う。価格は「単価（購入した単位あたり）」または「合計金額」のどちらかで受け取り、在庫単位あたりの unit_price に換算して保存する。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-BR-17 | 購入時、新しい在庫エントリの期限日が、同じ商品の既存の在庫エントリの最も早い期限日より前なら、レスポンスに警告を付ける（登録は行う）。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-18 | 在庫単位の変更: 在庫エントリまたは履歴を持つ商品の在庫単位を変更するには、旧単位から新単位への換算が解決できる必要がある。変更時は既存の在庫エントリの数量と unit_price を新単位へ換算する。換算できない場合は 422 で拒否する。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-BR-19 | 最低在庫の判定: min_stock_amount が 0 より大きい有効な商品について、`判定用の在庫数量 = 在庫エントリの数量の合計`（treat_opened_as_out_of_stock が true なら開封済みのエントリを除く）とする。`判定用の在庫数量 < min_stock_amount` のとき「最低在庫を下回った」とし、`不足量 = min_stock_amount - 判定用の在庫数量`（在庫単位、小数可）とする。等しい場合は下回っていない。 | submodules/grocy/changelog/52_2.5.0_2019-09-22.md、submodules/grocy/changelog/66_3.2.0_2022-02-11.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md |
| PAN-BR-20 | 買い物リストへの自動追加の条件: 設定 auto_add_below_min_stock が true のとき、消費・開封・廃棄・棚卸しの結果、商品が PAN-BR-19 で「最低在庫を下回った」状態になったら、既定の買い物リストにその商品を追加する。手動実行（「最低在庫を下回った商品を追加」）は設定に関係なく、下回っている全商品を対象にする。商品が無効なら追加しない。 | submodules/grocy/changelog/7_1.1.0_2017-04-21.md、submodules/grocy/changelog/67_3.3.0_2022-04-08.md、submodules/grocy/changelog/68_3.3.1_2022-06-10.md |
| PAN-BR-21 | 自動追加・手動実行で追加する数量: `必要量 = 不足量 - そのリストにある未購入（done=false）の同じ商品の数量の合計（在庫単位へ換算）`。必要量が 0 以下なら何もしない。必要量が 0 より大きいとき、同じ商品の未購入の項目があればその数量に加算し、なければ商品の購入単位で新しい項目を作る（origin=below_min_stock）。数量は購入単位へ換算し、小数を切り上げずにそのまま保存する。 | submodules/grocy/changelog/53_2.5.1_2019-09-28.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/77_4.4.0_2025-01-24.md |
| PAN-BR-22 | 買い物リストの表示用に数量を整数へ切り上げる場合も、保存する数量は変えない。切り上げはクライアント側の表示の選択とする。 | submodules/grocy/changelog/77_4.4.0_2025-01-24.md、submodules/grocy/changelog/82_4.7.0_2026-08-28.md |
| PAN-BR-23 | 冷凍・解凍（後回し）: is_freezer が false の場所から true の場所へ移すと、商品の default_due_days_after_freezing が 0 より大きければ期限日を「移動日 + 日数」、-1 なら null にする（0 なら変えない）。true から false へ移すと default_due_days_after_thawing に従って同様に変える。 | submodules/grocy/changelog/55_2.6.0_2020-01-31.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/77_4.4.0_2025-01-24.md |
| PAN-BR-24 | 買い物リストの消し込み: 項目を購入済みにするとき、在庫への登録を同時に行うかを選べる。登録する場合は項目の数量・単位で PAN-BR-16 の購入を行い、項目の done を true、done_at を現在日時にする。登録しない場合は done だけを変える。done を false に戻しても在庫は戻さない。 | submodules/grocy/changelog/39_1.23.0_2018-11-24.md、submodules/grocy/changelog/55_2.6.0_2020-01-31.md |
| PAN-BR-25 | 購入報告による消し込み（ingest_purchase）: 購入した品目ごとに在庫を加え、対象の買い物リスト（既定は既定のリスト）にある同じ商品の未購入の項目を、作成日時の古い順に消し込む。項目の数量（在庫単位へ換算）が購入量以下なら done=true にし、購入量から差し引いて次の項目へ進む。項目の数量が購入量より多ければ、項目の数量から購入量を差し引いた残りに減らし done は false のままにする。品目は product_id か name で商品を指定する。name は PAN-BR-01 と同じ正規化（大文字小文字と前後の空白を区別しない）で有効な商品名と完全一致で照合し、1 件に一致すればその商品とする。0 件または複数件に一致した品目は在庫に加えず、レスポンスで「未対応の品目」（候補の商品があればその一覧付き）として返す。他の品目の登録は続ける。 | README.md（§4.2 ingest_purchase）、submodules/grocy/changelog/39_1.23.0_2018-11-24.md |
| PAN-BR-26 | 既定の買い物リストは世帯に必ず 1 つあり、削除できない（名前は変更できる）。自動追加は既定のリストに対して行う。 | submodules/grocy/changelog/47_2.4.0_2019-05-10.md、submodules/grocy/changelog/65_3.1.3_2021-11-14.md |
| PAN-BR-27 | 買い物リストの項目は商品を参照しなくてもよい（自由記述の項目）。自由記述の項目は在庫と連動せず、消し込みで在庫は増えない。 | submodules/grocy/changelog/14_1.7.0_2018-04-15.md |
| PAN-BR-28 | 在庫を変更する操作（購入・消費・開封・廃棄・移動・棚卸し・在庫エントリの編集）は、すべて StockTransaction を記録し、操作した利用者と経路（source）を残す。1 回の操作の変更はすべて同じトランザクションで行い、途中で失敗したら全体を取り消す。 | submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-29 | 棚卸し（後回し）: 実数と現在の在庫数量の差を求め、増える場合は新しい在庫エントリ（期限日は PAN-BR-06 で決める）を作り、減る場合は PAN-BR-11 の順で引く。履歴の type は inventory_correction とする。 | submodules/grocy/changelog/55_2.6.0_2020-01-31.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md |
| PAN-BR-30 | 取り消し（後回し）: 取り消しは correlation_id 単位で行い、在庫エントリを操作前の状態（数量・開封状態・期限日・保管場所）に戻し、履歴の undone を true にする。取り消し後に同じ在庫エントリへ別の操作があった場合は 409 で拒否する。 | submodules/grocy/changelog/38_1.22.0_2018-10-27.md、submodules/grocy/changelog/60_3.0.0_2020-12-22.md、submodules/grocy/changelog/65_3.1.3_2021-11-14.md |

## LifePipe のワークフローとの関係

- get_morning_briefing: 期限の状態が due_soon（既定 3 日以内、今日が期限日のものを含む）・overdue・expired の在庫エントリを、商品名・保管場所・数量（在庫単位）・期限日・期限の種類つきで提供する（PAN-UC-11、PAN-BR-07、PAN-BR-08）。expired は「廃棄の候補」、overdue は「早めに使う候補」として区別できるようにする。
- ingest_purchase: 食材・消耗品の品目を受け取り、在庫への加算と買い物リストの消し込みを 1 回のリクエストで行う（PAN-UC-16、PAN-BR-25）。商品名から商品を引く検索（PAN-UC-02）と、未登録の品目の商品登録（PAN-UC-01）も使う。
- prepare_outing: 既定の買い物リストの未購入の項目（商品名・数量・単位・商品グループ）と、最低在庫を下回っているがリストに載っていない商品の不足量を提供する（PAN-UC-12、PAN-UC-14、PAN-BR-19、PAN-BR-21）。外出先のタスクは tasks が提供する。

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| products | 一覧（フィルタ: q（名前の部分一致）、location_id、product_group_id、in_stock、active）、作成、取得、更新、削除 | PAN-UC-01, PAN-UC-02 | 取得では在庫の要約（在庫数量、開封済み数量、次の期限日、最低在庫を下回っているか）を含める |
| products/{id}/stock | 取得 | PAN-UC-10 | 商品の在庫数量と在庫エントリの一覧 |
| products/{id}/purchase | 実行（数量、単位、期限日、保管場所、購入日、価格、メモ） | PAN-UC-06 | PAN-BR-06, PAN-BR-10, PAN-BR-16, PAN-BR-17。警告はレスポンスに含める |
| products/{id}/consume | 実行（数量、単位、保管場所、stock_entry_id、spoiled） | PAN-UC-07, PAN-UC-09 | 廃棄は spoiled=true。PAN-BR-11〜15 |
| products/{id}/open | 実行（数量、単位、保管場所、stock_entry_id） | PAN-UC-08 | PAN-BR-14 |
| products/{id}/transfer | 実行（数量、単位、移動元、移動先、stock_entry_id） | PAN-UC-21 | 後回し。PAN-BR-23 |
| products/{id}/inventory | 実行（実数、単位、期限日、保管場所） | PAN-UC-20 | 後回し。PAN-BR-29 |
| products/{id}/merge | 実行（統合先の商品 ID） | PAN-UC-28 | 後回し |
| product-groups | 一覧、作成、取得、更新、削除 | PAN-UC-26 | 後回し |
| quantity-units | 一覧、作成、取得、更新、削除 | PAN-UC-03 | 商品や換算から参照されている単位は削除できない（409） |
| quantity-unit-conversions | 一覧（フィルタ: product_id、quantity_unit_id）、作成、取得、更新、削除 | PAN-UC-04 | 逆向きの換算は自動で管理する（PAN-BR-09） |
| products/{id}/quantity-units | 一覧 | PAN-UC-04, PAN-UC-06 | その商品で使える単位と、在庫単位への factor（PAN-BR-10 で解決した値） |
| locations | 一覧、作成、取得、更新、削除 | PAN-UC-05 | 在庫エントリや商品から参照されている場所は削除できない（409） |
| stock | 一覧（フィルタ: location_id、product_group_id、below_min_stock） | PAN-UC-10 | 商品ごとの在庫の要約 |
| stock-entries | 一覧（フィルタ: product_id、location_id、opened）、取得、更新 | PAN-UC-10, PAN-UC-22 | 更新は後回し |
| stock/due | 一覧（フィルタ: within_days、status=due_soon/overdue/expired、location_id） | PAN-UC-11 | 在庫エントリ単位、期限日の昇順（PAN-BR-08） |
| stock/missing | 一覧 | PAN-UC-12 | 最低在庫を下回った商品と不足量（在庫単位と購入単位の両方）（PAN-BR-19） |
| stock-transactions | 一覧（フィルタ: product_id、type、spoiled、from、to、user_id） | PAN-UC-18 | |
| stock-transactions/{correlation_id}/undo | 実行 | PAN-UC-23 | 後回し。PAN-BR-30 |
| purchases | 実行（品目の配列: product_id または name、数量、単位、期限日、保管場所、価格。shopping_list_id） | PAN-UC-16 | ingest_purchase 用の一括登録と消し込み。結果に、登録した在庫エントリ、消し込んだ項目、未対応の品目を返す（PAN-BR-25） |
| shopping-lists | 一覧、作成、取得、更新、削除 | PAN-UC-25 | MVP では既定のリストの取得と更新のみ。既定のリストは削除不可（PAN-BR-26） |
| shopping-lists/{id}/items | 一覧（フィルタ: done、product_group_id）、作成、取得、更新、削除 | PAN-UC-14 | 商品グループ順の並び替えは後回し |
| shopping-lists/{id}/items/{item_id}/done | 実行（add_to_stock、期限日、保管場所、価格） | PAN-UC-15 | PAN-BR-24 |
| shopping-lists/{id}/add-missing-products | 実行 | PAN-UC-13 | PAN-BR-20, PAN-BR-21 |
| shopping-lists/{id}/add-overdue-products | 実行（status=overdue/expired） | PAN-UC-24 | 後回し |
| shopping-lists/{id}/clear | 実行（done_only、既定 true） | PAN-UC-17 | |
| settings | 取得、更新 | PAN-UC-19 | due_soon_days、auto_add_below_min_stock |

## 対象外

| 機能 | 理由 |
| --- | --- |
| レシピ（材料の在庫充足の判定、不足材料の買い物リスト追加、期限の近い材料を使うレシピの点数付け、自家製品の在庫登録） | Issue #18 の MVP に含まれず、在庫管理より範囲が広い。将来は pantry の在庫・買い物リストの API を使う別ドメインとして検討する |
| 献立（食事の計画、献立からの買い物リスト追加） | レシピに依存するため、レシピと同じ扱いとする |
| 家事（定期的な家事の記録・担当者の割り当て） | tasks ドメインの担当 |
| タスク（ToDo リスト） | tasks ドメインの担当 |
| バッテリー（充電の記録・次の充電予定） | 消費財の在庫ではない。長期保有品として扱うなら inventory ドメインの検討対象 |
| 家庭用機器（取扱説明書などの保管） | 長期保有品であり inventory ドメインの担当 |
| カレンダー（期限・家事・タスクの統合表示、iCal 配信） | 予定の集約は LifePipe のワークフロー（get_morning_briefing）が行う |
| 店舗の管理と店舗ごとの価格履歴、支出レポート | 支出の集計は pantry の責務外。購入価格は在庫エントリの任意項目として記録するだけにする |
| 利用者定義の項目・オブジェクト（Userfields） | API の項目を固定し、OpenAPI で型を定義できるようにするため |
| 親商品・子商品（子商品の在庫を親商品で合算、親商品での最低在庫の集約、子商品による代替消費） | MVP の判定ルールが複雑になるため。必要になったら後回しの機能として追加する |
| 容器の重さを含めた計量による消費（風袋の扱い） | 利用頻度が低く、数量の入力規則が複雑になるため |
| ラベル印刷・サーマルプリンタへの印刷・Grocycode | 周辺機器の連携であり、API の要件ではない |
| 外部サービスによるバーコード検索（Open Food Facts など） | 外部依存を増やすため。バーコードによる商品特定自体は後回し（PAN-UC-27） |
| スキャンモード、入力の短縮記法、キーボードショートカット、画面の表示設定 | 画面（UI）の機能であり、API の要件ではない |
| 利用者の管理・権限・認証方式（LDAP、リバースプロキシ認証、API キー） | 認証・認可は LifePipe のゲートウェイ側で共通に扱う。pantry は操作した利用者の ID を受け取って履歴に残すだけにする |

## 出典

- submodules/grocy/README.md
- submodules/grocy/changelog/6_1.0.1_2017-04-20.md
- submodules/grocy/changelog/7_1.1.0_2017-04-21.md
- submodules/grocy/changelog/14_1.7.0_2018-04-15.md
- submodules/grocy/changelog/33_1.19.0_2018-09-24.md
- submodules/grocy/changelog/38_1.22.0_2018-10-27.md
- submodules/grocy/changelog/39_1.23.0_2018-11-24.md
- submodules/grocy/changelog/45_2.2.0_2019-03-10.md
- submodules/grocy/changelog/47_2.4.0_2019-05-10.md
- submodules/grocy/changelog/52_2.5.0_2019-09-22.md
- submodules/grocy/changelog/53_2.5.1_2019-09-28.md
- submodules/grocy/changelog/55_2.6.0_2020-01-31.md
- submodules/grocy/changelog/60_3.0.0_2020-12-22.md
- submodules/grocy/changelog/61_3.0.1_2021-01-05.md
- submodules/grocy/changelog/62_3.1.0_2021-07-16.md
- submodules/grocy/changelog/63_3.1.1_2021-08-21.md
- submodules/grocy/changelog/65_3.1.3_2021-11-14.md
- submodules/grocy/changelog/66_3.2.0_2022-02-11.md
- submodules/grocy/changelog/67_3.3.0_2022-04-08.md
- submodules/grocy/changelog/68_3.3.1_2022-06-10.md
- submodules/grocy/changelog/69_3.3.2_2022-11-12.md
- submodules/grocy/changelog/70_4.0.0_2023-07-29.md
- submodules/grocy/changelog/74_4.1.0_2024-02-09.md
- submodules/grocy/changelog/76_4.3.0_2024-12-23.md
- submodules/grocy/changelog/77_4.4.0_2025-01-24.md
- submodules/grocy/changelog/81_4.6.0_2026-03-06.md
- submodules/grocy/changelog/82_4.7.0_2026-08-28.md
- https://grocy.info/
- README.md（§4 コアワークフロー）
- https://github.com/UtakataKyosui/LifePipe/issues/18（pantry の MVP の範囲）
