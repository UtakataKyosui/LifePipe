# inventory: 物品・固定資産管理 の要件

参考元: Homebox（AGPL-3.0）。ソースコードは参照していない。

表の出典欄では、`en/` は `submodules/homebox/docs/src/content/docs/en/` を表す。`LifePipe` とある項目は参考元の文書に記述がなく、LifePipe 側で定めた要件である。

## 責務

持つデータ:

- 長期保有する物品（家電、家具、工具、カメラなど）の台帳: 名前、説明、数量、メーカー・型番・シリアル番号、購入情報（購入日・購入元・価格）、保証情報、保険加入の有無、売却・譲渡の記録、備考
- 保管場所の階層（部屋 > 棚 > 引き出し など）と、物品がどこにあるか
- タグ（参考元では label。印刷用ラベルと区別するため本書ではタグと呼ぶ）
- カスタムフィールド（物品・保管場所ごとの任意の名前と値）
- 添付ファイル（写真、取扱説明書、レシート、保証書など）
- 資産番号（貼り付け用の QR コードやラベルに印字する、人が読める番号）
- メンテナンス記録と予定（後回し）

持たないデータ（他ドメインの責務）:

- 食材・日用消耗品の在庫と賞味期限、買い物リスト → pantry
- 衣類とコーディネート → wardrobe
- 固定費・サブスクリプションの支払い → subscriptions 系ドメイン
- 購買メモや自由記述のメモ → notes
- 家事・タスクの予定 → tasks
- レシート画像の文字認識や品目の振り分け判定 → LifePipe ゲートウェイ（ingest_purchase）。inventory は振り分け済みの品目を受け取るだけにする。
- 利用者の認証・アカウント管理 → LifePipe ゲートウェイ側の共通基盤。inventory は呼び出し元を信頼済みとして扱う。

## 参考元の構成

- 機能のまとまり: 物品（items）、保管場所（locations）、両者を束ねるエンティティ種別（entity types）、タグ、カスタムフィールド、添付ファイル、資産番号、QR コード、ラベル印刷テンプレート、物品テンプレート、メンテナンス記録と通知、CSV インポート/エクスポート、部品表（BOM）のエクスポート、検索。
- データモデル: 物品と保管場所はどちらも「エンティティ」で、種別の「コンテナ（保管場所）として扱うか」の設定で区別する。保管場所も写真・タグ・カスタムフィールド・添付・メモ・資産番号を持てる。
- データの保存先: SQLite（既定）または PostgreSQL。添付ファイルはローカルディスク、S3 互換ストレージ、Google Cloud Storage、Azure Blob Storage のいずれか。
- 外部依存: 全文検索は DB 内検索（既定）か Meilisearch。通知は Shoutrrr 経由（Discord、Slack、SMTP、ntfy、汎用 Webhook など）。商品バーコードの照会に外部サービス（BarcodeSpider、Open Food Facts 系）。ラベル画像の生成を外部 Web サービスに委ねる設定と、サーバー側でラベルプリンタを動かすコマンド設定がある。画像のサムネイルを生成する。変更通知は WebSocket（entity.mutation イベント）。
- 認証方式: ユーザー名とパスワード、OIDC による SSO、API キー（サーバー側の秘密値で HMAC したハッシュを保存）。認証試行には回数制限がある。
- マルチユーザーの単位: 「コレクション」（旧称 group）。登録したユーザーには既定のコレクションが作られ、招待リンクで他のユーザーを同じコレクションに参加させる。1 インスタンスで複数のコレクションを持てる。物品・場所・種別・タグはコレクション単位で管理し、検索もコレクションをまたがない。

## エンティティ

### Location（保管場所）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID）。サーバーが採番する |
| name | string | 必須 | 名前。1〜255 文字。例: 「書斎」「棚B」 |
| description | string | 任意 | 説明（Markdown） |
| parent_id | 参照(Location) | 任意 | 親の保管場所。空なら最上位 |
| kind | string | 任意 | 場所の種類の目安（例: room、shelf、box）。自由入力 |
| notes | string | 任意 | 備考（Markdown、1000 文字まで） |
| asset_id | string | 任意 | 資産番号（`000-001` 形式）。空なら番号なし |
| tag_ids | array<参照(Tag)> | 任意 | 付与したタグ |
| custom_fields | array<CustomField> | 任意 | カスタムフィールド |
| path | array<LocationRef> | 読み取り専用 | 最上位から自分までの祖先の並び（id と name） |
| item_count | integer | 読み取り専用 | この場所に直接置かれた物品の数 |
| total_value | number | 読み取り専用 | 配下（子孫の場所を含む）の物品の評価額合計。BR-12 で計算 |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### Item（物品）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID）。サーバーが採番する |
| name | string | 必須 | 名前。1〜255 文字 |
| description | string | 任意 | 説明（Markdown、1000 文字まで） |
| location_id | 参照(Location) | 必須 | 置いてある保管場所 |
| parent_item_id | 参照(Item) | 任意 | 親の物品（例: カメラ本体に対する交換レンズ）。BR-06〜BR-08 |
| quantity | integer | 必須 | 数量。0 以上。既定値 1 |
| asset_id | string | 任意 | 資産番号（`000-001` 形式）。BR-15〜BR-17 |
| manufacturer | string | 任意 | メーカー |
| model_number | string | 任意 | 型番 |
| serial_number | string | 任意 | シリアル番号 |
| purchase_date | date | 任意 | 購入日 |
| purchase_from | string | 任意 | 購入元（店舗名・サイト名） |
| purchase_price | number | 任意 | 購入価格（1 個あたり）。0 以上 |
| currency | string | 任意 | 通貨（ISO 4217 の 3 文字コード）。省略時はインスタンスの既定通貨 |
| lifetime_warranty | boolean | 任意 | 永久保証か。既定値 false |
| warranty_expires | date | 任意 | 保証期限（この日まで有効） |
| warranty_details | string | 任意 | 保証内容の説明（延長保証の加入先など） |
| warranty_status | enum(none, active, expiring_soon, expired, lifetime) | 読み取り専用 | 保証の状態。BR-10 で計算 |
| insured | boolean | 任意 | 保険の対象か。既定値 false |
| sold_date | date | 任意 | 売却・譲渡・廃棄した日 |
| sold_to | string | 任意 | 売却・譲渡の相手 |
| sold_price | number | 任意 | 売却価格。0 以上 |
| sold_notes | string | 任意 | 売却・処分に関する備考（1000 文字まで） |
| archived | boolean | 任意 | アーカイブ済みか。既定値 false。BR-14 |
| notes | string | 任意 | 備考（Markdown、1000 文字まで） |
| tag_ids | array<参照(Tag)> | 任意 | 付与したタグ |
| custom_fields | array<CustomField> | 任意 | カスタムフィールド |
| primary_photo_id | 参照(Attachment) | 読み取り専用 | 代表写真 |
| import_ref | string | 任意 | CSV インポートの重複判定キー（100 文字まで）。BR-24 |
| source_ref | string | 任意 | 外部連携（ingest_purchase）の重複判定キー（100 文字まで）。BR-27 |
| location_path | array<LocationRef> | 読み取り専用 | 置き場所の最上位からの経路 |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### Tag（タグ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID） |
| name | string | 必須 | 名前。1〜255 文字。BR-18 |
| description | string | 任意 | 説明 |
| color | string | 任意 | 表示色（`#RRGGBB`） |
| item_count | integer | 読み取り専用 | このタグが付いた物品の数 |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### CustomField（カスタムフィールド。Item・Location に埋め込む値オブジェクト）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| name | string | 必須 | フィールド名。1〜255 文字。例: 「消費電力」「購入時の注文番号」 |
| type | enum(text) | 必須 | 値の型。MVP は text のみ。BR-20 |
| value | string | 必須 | 値。1000 文字まで |

### Attachment（添付ファイル）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID） |
| owner_type | enum(item, location) | 必須 | 添付先の種類 |
| owner_id | 参照(Item) または 参照(Location) | 必須 | 添付先 |
| kind | enum(photo, manual, receipt, warranty, other) | 必須 | 用途。写真、取扱説明書、レシート、保証書、その他 |
| title | string | 必須 | 表示名。省略時はファイル名 |
| file_name | string | 必須 | 元のファイル名 |
| content_type | string | 必須 | MIME タイプ |
| size_bytes | integer | 読み取り専用 | ファイルサイズ |
| primary | boolean | 任意 | 代表写真か（kind が photo のときのみ）。BR-22 |
| has_thumbnail | boolean | 読み取り専用 | サムネイルが生成済みか |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### MaintenanceEntry（メンテナンス記録。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID） |
| item_id | 参照(Item) | 必須 | 対象の物品 |
| name | string | 必須 | 作業名（例: フィルター交換） |
| description | string | 任意 | 作業内容 |
| scheduled_date | date | 任意 | 予定日 |
| completed_date | date | 任意 | 実施日 |
| cost | number | 任意 | 費用。0 以上 |
| status | enum(scheduled, completed, overdue) | 読み取り専用 | BR-29 で計算 |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### ItemTemplate（物品テンプレート。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID） |
| name | string | 必須 | テンプレート名 |
| description | string | 任意 | 説明 |
| defaults | object | 必須 | 物品作成時に入れる既定値（name、description、quantity、manufacturer、model_number、tag_ids、custom_fields、location_id など Item の入力項目の部分集合） |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### LabelTemplate（ラベル印刷テンプレート。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 識別子（UUID） |
| name | string | 必須 | テンプレート名 |
| description | string | 任意 | 説明 |
| width_mm | number | 必須 | ラベル幅（mm） |
| height_mm | number | 必須 | ラベル高さ（mm） |
| dpi | integer | 必須 | 解像度。既定値 300 |
| orientation | enum(portrait, landscape) | 必須 | 向き |
| elements | array<LabelElement> | 必須 | 配置要素（text、barcode、rect、line、image）。位置・サイズ・回転を持つ。text は差し込み項目を含められる。barcode は種類（qr、datamatrix、code128、code39、ean13、ean8、upca）と符号化する元データを持つ |
| sheet_layout | object | 任意 | 台紙印刷時の用紙サイズ、行数・列数、余白、間隔、印刷位置の補正量 |
| is_default | boolean | 任意 | 利用者の既定テンプレートか |
| created_at | date-time | 読み取り専用 | 作成日時 |
| updated_at | date-time | 読み取り専用 | 更新日時 |

### PurchaseIngestion（購入品の取り込み結果。ingest_purchase の応答）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| source_ref | string | 必須 | 取り込み元の識別子（レシート ID と行番号など） |
| result | enum(created, updated, skipped) | 必須 | 新規作成、既存の更新、重複のため何もしなかった |
| item_id | 参照(Item) | 必須 | 対象の物品 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| INV-UC-01 | 保管場所を作成する（親を指定して入れ子にできる） | MVP | en/user-guide/locations.mdx |
| INV-UC-02 | 保管場所の名前・説明・備考・タグ・カスタムフィールドを編集する | MVP | en/user-guide/locations.mdx |
| INV-UC-03 | 保管場所を別の親の下へ移動する（配下ごと移る） | MVP | en/user-guide/locations.mdx, en/advanced/entity-merge-upgrade.mdx |
| INV-UC-04 | 保管場所を削除する | MVP | en/user-guide/locations.mdx |
| INV-UC-05 | 保管場所の階層をツリーで取得する（物品を含めることもできる） | MVP | en/advanced/entity-merge-upgrade.mdx |
| INV-UC-06 | 保管場所の詳細（経路、子の場所、置かれた物品、評価額合計）を見る | MVP | en/user-guide/locations.mdx |
| INV-UC-07 | 物品を登録する（名前、説明、場所、数量、メーカー・型番・シリアル番号、購入日・購入元・価格、保証、タグ、カスタムフィールド） | MVP | en/user-guide/items.mdx, en/advanced/import-csv.mdx, README.md |
| INV-UC-08 | 物品を編集する（売却・処分の記録を含む） | MVP | en/user-guide/items.mdx |
| INV-UC-09 | 物品を別の保管場所へ移動する | MVP | en/advanced/entity-merge-upgrade.mdx |
| INV-UC-10 | 物品を削除する | MVP | en/user-guide/items.mdx |
| INV-UC-11 | 物品をキーワード・タグ・場所・カスタムフィールド・保証状態で検索し、どこにあるかを経路付きで知る | MVP | en/quick-start/configure/search.mdx, en/advanced/entity-merge-upgrade.mdx |
| INV-UC-12 | 資産番号で物品を引く（`#000-001` 検索、資産番号 URL の解決） | MVP | en/user-guide/tips-tricks.mdx, en/user-guide/label-templates.mdx |
| INV-UC-13 | タグを作成・編集・削除し、物品と保管場所に付け外しする | MVP | README.md, en/user-guide/entity-types.mdx |
| INV-UC-14 | 物品・保管場所に写真や書類を添付し、取得・更新・削除する | MVP | en/advanced/entity-merge-upgrade.mdx, en/user-guide/locations.mdx |
| INV-UC-15 | 物品・保管場所・資産番号の QR コード画像を取得する | MVP | en/user-guide/tips-tricks.mdx |
| INV-UC-16 | 物品に親子関係を付ける（付属品を本体にぶら下げる） | MVP | en/advanced/entity-merge-upgrade.mdx, en/advanced/import-csv.mdx |
| INV-UC-17 | 使われているカスタムフィールド名と、その名前で使われている値の一覧を得る（入力補完用） | MVP | en/advanced/entity-merge-upgrade.mdx |
| INV-UC-18 | 購入した長期保有品を一括で登録する（ingest_purchase） | MVP | LifePipe（Issue #27、README §4） |
| INV-UC-19 | 保証期限が近い物品の一覧を得る | MVP | README.md, LifePipe |
| INV-UC-20 | 物品を複製する | 後回し | en/advanced/entity-merge-upgrade.mdx |
| INV-UC-21 | 物品をアーカイブし、通常の一覧から外す | 後回し | en/advanced/entity-merge-upgrade.mdx |
| INV-UC-22 | 資産番号が未採番（0）の物品にまとめて番号を振る | 後回し | en/user-guide/tips-tricks.mdx |
| INV-UC-23 | CSV/TSV から物品・保管場所・タグを取り込む（重複判定と更新あり） | 後回し | en/advanced/import-csv.mdx |
| INV-UC-24 | 物品を CSV でエクスポートする | 後回し | en/advanced/import-csv.mdx, https://homebox.software/en/ |
| INV-UC-25 | メンテナンス予定・実施記録を登録し、予定日に通知する | 後回し | en/user-guide/notifiers.mdx, en/user-guide/tips-tricks.mdx |
| INV-UC-26 | 物品テンプレートを作り、物品作成時に既定値を入れる | 後回し | en/user-guide/entity-types.mdx, https://homebox.software/en/ |
| INV-UC-27 | ラベル印刷テンプレートを作り、物品・保管場所のラベルを PNG/PDF で出力する | 後回し | en/user-guide/label-templates.mdx |
| INV-UC-28 | 部品表（BOM）をエクスポートする | 後回し | https://homebox.software/en/ |

## 業務ルール

| ID | ルール | 出典 |
| --- | --- | --- |
| INV-BR-01 | 保管場所の親は保管場所に限る。物品を保管場所の親にはできない。保管場所の `parent_id` に存在しない ID を指定したら 422 で拒否する | en/user-guide/locations.mdx |
| INV-BR-02 | 保管場所の階層に循環を作らない。保管場所 A の親に、A 自身または A の子孫を指定したら 409 で拒否する。判定は親をたどって最上位まで上がり、途中に A が現れるかで行う | en/user-guide/locations.mdx, LifePipe |
| INV-BR-03 | 保管場所の移動は `parent_id` の変更で行う。子の場所と置かれた物品は移動した場所に付いたまま一緒に移り、配下すべての `path`・`location_path` は移動後の経路で返す。`parent_id` を空にすると最上位に移る | en/user-guide/locations.mdx, en/advanced/entity-merge-upgrade.mdx |
| INV-BR-04 | 同じ親の下で保管場所の名前は重複させない（大文字小文字を区別せず比較）。重複したら 409。経路の表記は名前を ` / ` でつないだもの（例: `自宅 / 書斎 / 棚B`）で、CSV インポートでは同じ経路を同じ場所として扱う | en/advanced/import-csv.mdx, LifePipe |
| INV-BR-05 | 保管場所の削除は、子の場所も物品も無いときだけ許す。残っていれば 409 を返し、先に移動させる。参考元は配下の物品も一緒に削除するが、LifePipe では誤操作による台帳の消失を防ぐためこの方式にする | en/user-guide/locations.mdx, LifePipe |
| INV-BR-06 | 物品は親の物品を 1 つ持てる（`parent_item_id`）。親になれるのは物品だけで、保管場所を物品の中に入れることはできない。物品の親子にも循環を作らない（自分自身・自分の子孫を親にしたら 409） | en/user-guide/locations.mdx, en/advanced/entity-merge-upgrade.mdx |
| INV-BR-07 | 子の物品の `location_id` は親の物品と同じにする。子の物品を作成・更新するときに `location_id` を省略したら親の場所を入れ、親と違う場所を指定したら 422 で拒否する。親の物品を移動したら、子孫の物品の `location_id` も同じ場所に更新する | en/advanced/entity-merge-upgrade.mdx（`syncChildEntityLocations`）, LifePipe |
| INV-BR-08 | 親の物品を削除するとき、子の物品は削除せず `parent_item_id` を空にして同じ場所に残す | LifePipe |
| INV-BR-09 | `lifetime_warranty` が true のとき `warranty_expires` は空でなければならない（両方指定したら 422）。`warranty_expires` と `purchase_date` が両方あるとき、保証期限は購入日以降でなければならない | en/advanced/import-csv.mdx, LifePipe |
| INV-BR-10 | `warranty_status` は基準日（既定は当日、インスタンスのタイムゾーン）から次の順で決める。(1) `lifetime_warranty` が true なら lifetime。(2) `warranty_expires` が空なら none。(3) 基準日 > 保証期限なら expired。(4) 保証期限 − 基準日 ≤ N 日なら expiring_soon（N は既定 30、検索時に指定可）。(5) それ以外は active。保証期限の当日は有効に含める。売却済み（`sold_date` あり）の物品は保証期限が近づいても通知対象にしない | en/advanced/import-csv.mdx, README.md, LifePipe |
| INV-BR-11 | 数量は 0 以上の整数、価格（購入・売却）は 0 以上の数値。`purchase_price` は 1 個あたりの価格として扱う | en/advanced/import-csv.mdx, en/advanced/entity-merge-upgrade.mdx |
| INV-BR-12 | 評価額合計は、対象範囲の物品のうち売却済みでないものについて `purchase_price × quantity` を合計した値。価格が空の物品は 0 として数える。通貨が混在する場合は通貨ごとに合計を返す。保管場所の評価額合計は子孫の場所に置かれた物品を含む | en/advanced/entity-merge-upgrade.mdx, en/user-guide/locations.mdx, LifePipe |
| INV-BR-13 | `sold_date` が入った物品は売却・処分済みとして扱う。台帳からは消さず、一覧では既定で表示する。`sold_to`・`sold_price`・`sold_notes` は `sold_date` があるときだけ意味を持つ | en/user-guide/items.mdx, en/advanced/import-csv.mdx |
| INV-BR-14 | `archived` が true の物品は、一覧・検索で `include_archived=true` を指定したときだけ返す | en/advanced/entity-merge-upgrade.mdx |
| INV-BR-15 | 資産番号は `DDD-DDD`（数字 3 桁、ハイフン、数字 3 桁）の形式。自動採番が有効（既定）なら、物品の作成・インポート時に資産番号を指定しなければ、既存の最大番号の次の番号を振る。例: 最大が `000-041` なら `000-042` | en/user-guide/tips-tricks.mdx, en/quick-start/configure/index.mdx |
| INV-BR-16 | 資産番号の空欄は「番号を持たない」を意味し、自動採番の対象外にする。`000-000`（0）は「未採番」を意味し、一括採番（INV-UC-22）で作成日時の古い順に次の番号を振る。資産番号は一意性を強制しない（重複を許す）が、自動採番は重複しない番号を選ぶ | en/user-guide/tips-tricks.mdx |
| INV-BR-17 | 資産番号 URL（`/a/<資産番号>`）は、その時点でその資産番号を持つ物品または保管場所に解決する。資産番号を別の物品に付け替えても、貼ったラベルの QR コードはそのまま使える。重複している場合は作成日時の古いものを返す | en/user-guide/label-templates.mdx, LifePipe |
| INV-BR-18 | タグ名は重複させない（大文字小文字を区別せず比較、重複は 409）。タグを削除すると、物品・保管場所からの付与も外れる。物品・保管場所は削除されない | README.md, LifePipe |
| INV-BR-19 | カスタムフィールドは物品・保管場所ごとに任意の数だけ持てる。名前は 1〜255 文字、値は 1000 文字まで。同じ物品の中で名前は重複させない（大文字小文字を区別せず比較、重複は 422）。値が空のフィールドは保存しない | en/user-guide/tips-tricks.mdx, en/advanced/import-csv.mdx, LifePipe |
| INV-BR-20 | カスタムフィールドの型は MVP では text のみ。値が `https://` で始まる URL、または Markdown のリンク形式 `[表示名](URL)` のとき、クライアントはリンクとして表示できる（サーバーは値をそのまま保存する） | en/user-guide/tips-tricks.mdx |
| INV-BR-21 | カスタムフィールドによる検索は `名前=値` の完全一致（大文字小文字を区別しない）。複数指定したら AND で絞り込む。フィールド名一覧と、指定した名前の値一覧（重複なし）を返す API を用意する | en/advanced/entity-merge-upgrade.mdx |
| INV-BR-22 | 添付ファイルは 1 件あたり既定 10 MB まで（設定で変更可）。超えたら 413。物品・保管場所ごとに代表写真は最大 1 件で、新しく代表に指定すると前の代表は外れる。代表が無いときは最初に追加した写真を代表として扱う。PNG・JPEG・AVIF・WEBP・GIF の写真にはサムネイルを作る | en/quick-start/configure/index.mdx, LifePipe |
| INV-BR-23 | キーワード検索は、空白で区切った語すべてが物品のいずれかの項目（名前、説明、備考、メーカー、型番、シリアル番号、カスタムフィールドの値など）に含まれるものを返す。二重引用符で囲んだ語句は語順どおりに一致させる。大文字小文字は区別しない。先頭が `#` なら資産番号で検索する。場所で絞り込むときは既定で子孫の場所も含め、`include_descendants=false` で直下だけにする。タグの絞り込みは指定タグのいずれかを持つもの、`negate_tags=true` で指定タグを持たないものを返す | en/quick-start/configure/search.mdx, en/advanced/entity-merge-upgrade.mdx, LifePipe |
| INV-BR-24 | CSV/TSV インポート: 区切り文字（カンマまたはタブ）で判別し、拡張子は問わない。列名は大文字小文字を区別する。`import_ref` が既存の物品と一致したら、その物品を更新し新規作成しない。場所列は ` / ` 区切りの経路で、無い場所は階層ごと作る。タグ列はカンマ区切りで、無いタグは作る。カスタムフィールド列は列名の接頭辞の後をフィールド名とし、空のセルは無視する。日付は `YYYY-MM-DD`、真偽値は true/false・yes/no・1/0（大文字小文字を区別しない）。添付ファイルと物品の親子関係は取り込まない | en/advanced/import-csv.mdx |
| INV-BR-25 | CSV エクスポートは物品ごとに 1 行で、インポートと同じ列を出す。場所は最上位からの経路で出す（参考元は直接の親だけを出す） | en/advanced/import-csv.mdx, LifePipe |
| INV-BR-26 | QR コードは、物品・保管場所の詳細画面 URL、または資産番号 URL（INV-BR-17）を符号化した PNG 画像として返す。資産番号を持つものは資産番号 URL を優先する。URL の基点はインスタンス設定の公開 URL を使う | en/user-guide/tips-tricks.mdx, en/user-guide/label-templates.mdx |
| INV-BR-27 | ingest_purchase による取り込みは品目ごとに `source_ref` で重複を判定する。同じ `source_ref` の物品があれば何もせず skipped を返す（同じレシートを再送しても二重登録しない）。保管場所の指定が無い品目は、インスタンス設定の「受け入れ用の場所」（既定名「未整理」、無ければ作る）に置く。数量 n・合計金額 t の行は `quantity = n`、`purchase_price = t ÷ n` として登録する | LifePipe（Issue #27、README §4） |
| INV-BR-28 | 1 回の取り込み要求に含まれる品目は 1 件ずつ独立に処理し、検証に失敗した品目があっても他の品目は登録する。応答で品目ごとの結果とエラーを返す | LifePipe |
| INV-BR-29 | メンテナンスの状態: `completed_date` があれば completed、無く `scheduled_date` が基準日より前なら overdue、それ以外は scheduled。予定日当日の朝（参考元は 8 時頃）に、その日が予定日の作業をまとめて通知する（後回し） | en/user-guide/notifiers.mdx, en/user-guide/tips-tricks.mdx |
| INV-BR-30 | 物品の複製では、ID・資産番号・`import_ref`・`source_ref`・添付ファイルを引き継がず、それ以外の項目を写す。資産番号は INV-BR-15 で新たに振る（後回し） | en/advanced/entity-merge-upgrade.mdx, LifePipe |
| INV-BR-31 | ラベル印刷テンプレートの差し込み項目は名前、説明、備考、資産番号、シリアル番号、型番、メーカー、場所、場所の経路、タグ、数量、物品数、各種 URL、カスタムフィールド、印刷日時。値の無い項目と未知の項目は空文字として印字する。EAN・UPC のバーコードは数字だけを符号化できる（後回し） | en/user-guide/label-templates.mdx |

## LifePipe のワークフローとの関係

- ingest_purchase: 主な連携先。ゲートウェイがレシートや購入報告を品目に分け、長期保有品と判定した品目を `purchase-ingestions` にまとめて渡す。inventory は品目ごとに名前、購入日、購入元、単価、数量、通貨、保証期限、シリアル番号、タグ、保管場所を受け取って物品を登録し、品目ごとの結果（created / skipped と物品 ID）を返す（INV-UC-18、INV-BR-27、INV-BR-28）。レシート画像は登録後に添付ファイル（kind: receipt）として追加できる。
- get_morning_briefing: 必須の提供物は無い。任意で、保証期限が近い物品（`warranty_status=expiring_soon`）と、メンテナンス導入後は当日予定・期限切れのメンテナンスを提供できる（INV-UC-19、INV-UC-25）。
- prepare_outing: 提供するものは無い。

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| locations | 一覧 GET /locations（フィルタ: parent_id、root_only、q、tag_ids） | INV-UC-05, INV-UC-06 | 各要素に item_count、path を含める |
| locations | 作成 POST /locations | INV-UC-01 | INV-BR-01, INV-BR-04 |
| locations | 取得 GET /locations/{id} | INV-UC-06 | 子の場所、path、total_value を含める |
| locations | 更新 PATCH /locations/{id} | INV-UC-02, INV-UC-03 | parent_id の変更が移動。INV-BR-02, INV-BR-03 |
| locations | 削除 DELETE /locations/{id} | INV-UC-04 | 配下があれば 409。INV-BR-05 |
| locations/tree | 取得 GET /locations/tree（パラメータ: with_items、root_id） | INV-UC-05 | 入れ子の木構造で返す |
| items | 一覧・検索 GET /items（フィルタ: q、location_id、include_descendants、parent_item_id、tag_ids、negate_tags、fields（`名前=値` の配列）、warranty_status、warranty_expires_before、warranty_within_days、sold、include_archived。ページング: page、page_size。並び順: name、created_at、updated_at、purchase_date、warranty_expires） | INV-UC-11, INV-UC-19 | 応答に total と total_value を含める。INV-BR-10, INV-BR-12, INV-BR-23 |
| items | 作成 POST /items | INV-UC-07, INV-UC-16 | 資産番号の自動採番。INV-BR-06, INV-BR-07, INV-BR-09, INV-BR-15 |
| items | 取得 GET /items/{id} | INV-UC-11 | location_path、子の物品、添付の一覧を含める |
| items | 更新 PATCH /items/{id} | INV-UC-08, INV-UC-09, INV-UC-16, INV-UC-21 | location_id の変更が移動。子孫の物品も移る。INV-BR-07, INV-BR-13 |
| items | 削除 DELETE /items/{id} | INV-UC-10 | 子の物品は残す。INV-BR-08。添付ファイルも削除する |
| items | 複製 POST /items/{id}/duplicate | INV-UC-20 | 後回し。INV-BR-30 |
| tags | 一覧 GET /tags、作成 POST /tags、取得 GET /tags/{id}、更新 PATCH /tags/{id}、削除 DELETE /tags/{id} | INV-UC-13 | 付け外しは items・locations の tag_ids で行う。INV-BR-18 |
| custom-fields | 名前の一覧 GET /custom-fields（フィルタ: owner_type） | INV-UC-17 | INV-BR-21 |
| custom-fields | 値の一覧 GET /custom-fields/{name}/values | INV-UC-17 | 重複なし |
| items/{id}/attachments | 一覧 GET、追加 POST（multipart）、メタデータ更新 PATCH /{attachment_id}、削除 DELETE /{attachment_id} | INV-UC-14 | INV-BR-22 |
| locations/{id}/attachments | 一覧 GET、追加 POST（multipart）、メタデータ更新 PATCH /{attachment_id}、削除 DELETE /{attachment_id} | INV-UC-14 | INV-BR-22 |
| attachments | ファイル取得 GET /attachments/{id}/content、サムネイル取得 GET /attachments/{id}/thumbnail | INV-UC-14 | |
| assets | 解決 GET /assets/{asset_id} | INV-UC-12 | 物品または保管場所を返す。INV-BR-17 |
| assets | 一括採番 POST /assets/assign-unassigned | INV-UC-22 | 後回し。INV-BR-16 |
| qrcodes | 画像取得 GET /items/{id}/qrcode、GET /locations/{id}/qrcode、GET /assets/{asset_id}/qrcode | INV-UC-15 | image/png。INV-BR-26 |
| purchase-ingestions | 取り込み POST /purchase-ingestions | INV-UC-18 | 品目の配列を受け取り、品目ごとの PurchaseIngestion を返す。INV-BR-27, INV-BR-28 |
| imports | CSV 取り込み POST /imports/csv | INV-UC-23 | 後回し。作成・更新・スキップ件数と行ごとのエラーを返す。INV-BR-24 |
| exports | CSV 出力 GET /exports/items.csv | INV-UC-24 | 後回し。INV-BR-25 |
| items/{id}/maintenance | 一覧 GET、作成 POST、更新 PATCH /{entry_id}、削除 DELETE /{entry_id} | INV-UC-25 | 後回し。INV-BR-29 |
| maintenance | 一覧 GET /maintenance（フィルタ: status、scheduled_before） | INV-UC-25 | 後回し。get_morning_briefing 用 |
| item-templates | 一覧・作成・取得・更新・削除 | INV-UC-26 | 後回し |
| label-templates | 一覧・作成・取得・更新・削除、描画 POST /label-templates/{id}/render（対象 ID の配列、部数、出力形式 png/pdf） | INV-UC-27 | 後回し。INV-BR-31 |

## 対象外

- 複数コレクション（世帯・グループ）と招待リンクによる共有: LifePipe は単一の世帯で使う前提で、利用者の管理はゲートウェイ側に置く。
- 利用者登録・ログイン・OIDC・API キーの発行: ゲートウェイの共通基盤の責務。
- エンティティ種別（利用者が場所・物品の種類を定義し、コンテナかどうかを切り替える仕組み）: 場所と物品を別リソースに分けたため不要。場所の種類は自由入力の `kind` で足りる。
- 商品バーコードによる外部サービスでの商品情報照会: 外部サービスへの依存と利用者情報の送信が生じる。購入情報は ingest_purchase から受け取る。
- サーバー側でのラベルプリンタ操作と、外部ラベル生成サービスの呼び出し: 任意コマンドの実行や外部への送信を伴う。ラベル画像の出力までにとどめる。
- 通知の配信（Shoutrrr 相当）: 通知はゲートウェイの get_morning_briefing が担う。
- WebSocket による変更通知: MCP ゲートウェイからの呼び出しでは不要。
- Meilisearch などの外部全文検索エンジン: 家庭の規模では DB 内検索で足りる。
- 部品表（BOM）のエクスポート、カスタム通貨の追加: 利用頻度が低い。
- integer・boolean・timestamp 型のカスタムフィールド: 参考元でも未実装で、MVP は text で足りる。

## 出典

- submodules/homebox/README.md
- submodules/homebox/docs/src/content/docs/en/user-guide/index.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/items.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/locations.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/entity-types.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/label-templates.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/notifiers.mdx
- submodules/homebox/docs/src/content/docs/en/user-guide/tips-tricks.mdx
- submodules/homebox/docs/src/content/docs/en/advanced/import-csv.mdx
- submodules/homebox/docs/src/content/docs/en/advanced/entity-merge-upgrade.mdx
- submodules/homebox/docs/src/content/docs/en/advanced/external-label-service.mdx
- submodules/homebox/docs/src/content/docs/en/quick-start/index.mdx
- submodules/homebox/docs/src/content/docs/en/quick-start/configure/index.mdx
- submodules/homebox/docs/src/content/docs/en/quick-start/configure/storage.mdx
- submodules/homebox/docs/src/content/docs/en/quick-start/configure/search.mdx
- https://homebox.software/en/
- LifePipe README §4、GitHub Issue #27
