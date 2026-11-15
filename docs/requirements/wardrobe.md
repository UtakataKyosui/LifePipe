# wardrobe: 衣服・ワードローブ管理 の要件

参考元: Wardrowbe（MIT）。ソースコードは参照していない。

## 責務

wardrobe サービスは、世帯で持っている衣服のカタログを持つ記録システム（system of record）である。

持つデータ:

- 世帯と世帯メンバー（衣服の持ち主の単位）
- 衣服（種類・色・素材・季節・厚さ・場面・洗濯の要否などの属性）
- 衣服の画像（元画像。加工後の画像は後回し）
- 着用記録（いつ、誰が、どの服を着たか）と、そこから集計する着用回数
- 洗濯ステータスと洗濯記録
- 画像処理ジョブの状態（後回しの機能のために、項目だけ先に用意する）
- コーディネート（後回し）

持たないデータ（他ドメイン・外部の責務）:

- 天気・気温・降水確率: LifePipe のゲートウェイが気象 API から取得し、条件として wardrobe に渡す。wardrobe は位置情報を持たない。
- 予定: Google Calendar が持つ。ゲートウェイが予定を場面（occasion）に変換して wardrobe に渡す。
- レシート・購入の記録: 購入メモは notes、衣類以外の長期保有品は inventory が持つ。wardrobe は振り分けられた衣類の品目だけを受け取る。
- 通知の送信: LifePipe のワークフローが行う。
- 利用者の認証: LifePipe 共通の仕組み（edge）が行い、wardrobe は認証済みの利用者と世帯の ID を受け取る。

## 参考元の構成

| 観点 | 内容 | 出典 |
| --- | --- | --- |
| 主な機能 | 写真による衣服の登録と AI による属性の抽出、天気・場面・好みに合わせたコーディネート提案、定時の通知、世帯メンバーの衣服管理、着用履歴・評価・フィードバック、着用状況や色の分析、洗濯の管理、1着を起点にした組み合わせ（ペアリング） | `submodules/wardrowbe/README.md`（Features、Screenshots） |
| アプリの構成 | フロントエンド（Next.js）、バックエンド API（FastAPI）、AI ジョブ用の worker（arq）、背景除去用の image-worker（arq、rembg）。worker と image-worker はバックエンドと同じイメージで、起動コマンドだけが異なる | `submodules/wardrowbe/README.md`（Architecture、Upgrading）、`submodules/wardrowbe/k8s/README.md`（Deploy Application）、`compose.yaml`、`docs/local-stack.md` |
| データの保存先 | PostgreSQL（業務データ）。アップロード画像はファイルシステムのボリューム（k8s では既定 10Gi の PVC）。rembg のモデルは別ボリューム | `submodules/wardrowbe/README.md`（Architecture）、`submodules/wardrowbe/k8s/README.md`（Storage）、`docs/local-stack.md`（データの保存先） |
| ジョブキュー | Redis を arq のジョブキューとして使い、AI 解析と背景除去を非同期に処理する | `submodules/wardrowbe/README.md`（Architecture）、`docs/local-stack.md` |
| AI | OpenAI 互換 API（Ollama・OpenAI・LocalAI など）。画像から属性を抽出する vision モデルと、提案文を作る text モデルの2種類を使う。AI は全体または機能ごとに無効にでき、無効でも手動の登録・編集・着用記録・手動のコーディネート作成は動く。LifePipe の compose では既定の接続先がホストの Ollama | `submodules/wardrowbe/README.md`（AI Configuration、Running without internal AI）、`docs/local-stack.md` |
| 背景除去 | rembg（既定モデル u2net）か、HTTP の外部サービスを選べる。どちらも設定されていなければ、背景除去の操作は「未実装」を返す | `submodules/wardrowbe/README.md`（Background Removal） |
| 天気・位置 | 天気は Open-Meteo、地名の座標変換は OpenStreetMap Nominatim。座標はブラウザの位置情報から設定する | `submodules/wardrowbe/README.md`（Weather and location） |
| 通知 | 利用者が ntfy・Mattermost・メールのチャネルを登録する | `submodules/wardrowbe/README.md`（Notifications） |
| 認証 | 開発用ログイン、OIDC、forward-auth（TinyAuth・Authelia など）。1アカウントはプロバイダごとに1つのサインイン ID を持ち、検証済みメールが一致すれば同じアカウントに結び付ける。アカウントを無効化すると全トークンが拒否される。画像は有効期限付きの署名 URL で配る | `submodules/wardrowbe/README.md`（Authentication）、`submodules/wardrowbe/docs/sign-in-identities.md`、`submodules/wardrowbe/docs/forward-auth.md` |
| マルチユーザーの単位 | 世帯（family / household）。世帯メンバーの衣服をまとめて管理し、招待リンクで参加させる | `submodules/wardrowbe/README.md`（Features、Environment Variables の APP_URL）、https://wardrowbe.com/features |
| クラウド版との差 | 買う前の照合、複数着の一括撮影、不足アイテムの報告、着用確認、衣服の見直し（残す・手放す）、共有、試着プレビューはクラウド版だけの機能 | https://wardrowbe.com/features 、https://wardrowbe.com |

## エンティティ

### Household（世帯）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 世帯 ID（UUID） |
| name | string | ○ | 世帯名（例: 「山田家」） |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### Member（世帯メンバー）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | メンバー ID（UUID） |
| household_id | 参照(Household) | ○ | 所属する世帯 |
| user_id | string | - | LifePipe の認証で使う利用者 ID。ログインしない家族（子どもなど）は空 |
| display_name | string | ○ | 表示名（例: 「太郎」） |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### Item（衣服）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 衣服 ID（UUID） |
| household_id | 参照(Household) | ○ | 所属する世帯 |
| owner_member_id | 参照(Member) | ○ | 持ち主 |
| name | string | ○ | 名前（例: 「紺のオックスフォードシャツ」） |
| category | enum(top, bottom, one_piece, outerwear, innerwear, shoes, accessory, bag, other) | ○ | 種類。コーディネートでの役割と、洗濯までの着用回数の既定値を決める |
| subcategory | string | - | 細かい種類（例: 「シャツ」「デニム」） |
| colors | array<string> | - | 色（例: `navy`, `white`）。先頭を主な色とする |
| pattern | string | - | 柄（例: 「無地」「ストライプ」） |
| material | string | - | 素材（例: 「綿」「ウール」） |
| brand | string | - | ブランド |
| size | string | - | サイズ表記 |
| seasons | array<enum(spring, summer, autumn, winter)> | - | 着る季節。空は通年 |
| warmth | integer | ○ | 厚さ・暖かさ。1（薄手）〜5（厚手）。既定は 3 |
| min_temp | number | - | この服を着られる最低気温（℃）。設定すると warmth による判定より優先する |
| max_temp | number | - | この服を着られる最高気温（℃）。設定すると warmth による判定より優先する |
| water_resistant | boolean | ○ | 雨に向くか（撥水・防水）。既定は false |
| occasions | array<enum(casual, work, formal, sport, home)> | - | 向いている場面。空は casual と home だけとみなす |
| formality | integer | - | フォーマル度。1（部屋着）〜5（礼装） |
| notes | string | - | メモ（例: 「アイロン必要」） |
| wash_status | enum(clean, needs_wash, in_laundry) | ○ | 洗濯ステータス。既定は clean |
| wears_before_wash | integer | ○ | 洗濯が必要になるまでの着用回数。0 は洗濯管理の対象外。未指定なら category の既定値 |
| wears_since_wash | integer | ○ | 最後の洗濯の後に着た回数（読み取り専用） |
| wear_count | integer | ○ | 通算の着用回数（読み取り専用） |
| last_worn_on | date | - | 最後に着た日（読み取り専用） |
| last_washed_at | date-time | - | 最後に洗濯済みにした日時（読み取り専用） |
| status | enum(active, archived) | ○ | 所持状態。手放した服は archived |
| archived_at | date-time | - | アーカイブした日時 |
| primary_image_id | 参照(ItemImage) | - | 一覧に表示する画像 |
| source | enum(manual, purchase, import) | ○ | 登録の経路。購入の振り分けから登録したものは purchase |
| purchased_on | date | - | 購入日 |
| purchase_price | integer | - | 購入価格（通貨の最小単位。円なら円） |
| currency | string | - | ISO 4217 の通貨コード（例: `JPY`） |
| store | string | - | 購入店 |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### ItemImage（衣服の画像）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 画像 ID（UUID） |
| item_id | 参照(Item) | ○ | 対象の衣服 |
| kind | enum(original, thumbnail, background_removed) | ○ | 画像の種類。MVP は original だけを作る |
| source_image_id | 参照(ItemImage) | - | 加工元の画像（thumbnail・background_removed のとき） |
| content_type | enum(image/jpeg, image/png, image/webp) | ○ | 形式 |
| byte_size | integer | ○ | ファイルサイズ（バイト） |
| width | integer | - | 幅（px） |
| height | integer | - | 高さ（px） |
| storage_key | string | ○ | 保存先のキー（内部用。API では返さない） |
| url | string | ○ | 有効期限付きの取得 URL（取得時に発行する） |
| url_expires_at | date-time | ○ | url の有効期限 |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### ImageJob（画像処理ジョブ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | ジョブ ID（UUID） |
| item_id | 参照(Item) | ○ | 対象の衣服 |
| image_id | 参照(ItemImage) | ○ | 入力の画像 |
| type | enum(thumbnail, background_removal, ai_tagging) | ○ | 処理の種類 |
| status | enum(pending, running, succeeded, failed) | ○ | 状態 |
| attempts | integer | ○ | 試行回数 |
| error_message | string | - | 失敗の理由（個人のデータを含めない） |
| result_image_id | 参照(ItemImage) | - | 出力の画像（thumbnail・background_removal のとき） |
| suggested_attributes | string | - | AI が提案した属性（JSON 文字列。ai_tagging のとき） |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### WearLog（着用記録）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 着用記録 ID（UUID） |
| household_id | 参照(Household) | ○ | 所属する世帯 |
| member_id | 参照(Member) | ○ | 着た人 |
| worn_on | date | ○ | 着た日 |
| item_ids | array<参照(Item)> | ○ | 着た服（1着以上） |
| outfit_id | 参照(Outfit) | - | 元にしたコーディネート（後回し） |
| occasion | enum(casual, work, formal, sport, home) | - | 場面 |
| rating | integer | - | 評価。1〜5 |
| note | string | - | メモ |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### WashLog（洗濯記録）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 洗濯記録 ID（UUID） |
| item_id | 参照(Item) | ○ | 対象の衣服 |
| from_status | enum(clean, needs_wash, in_laundry) | ○ | 変更前の洗濯ステータス |
| to_status | enum(clean, needs_wash, in_laundry) | ○ | 変更後の洗濯ステータス |
| trigger | enum(wear_threshold, manual, washed) | ○ | 変更のきっかけ |
| changed_at | date-time | ○ | 変更日時 |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### Outfit（コーディネート。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | コーディネート ID（UUID） |
| household_id | 参照(Household) | ○ | 所属する世帯 |
| member_id | 参照(Member) | ○ | 着る人 |
| name | string | - | 名前（例: 「週末のカジュアル」） |
| item_ids | array<参照(Item)> | ○ | 構成する服 |
| occasion | enum(casual, work, formal, sport, home) | - | 場面 |
| source | enum(manual, ai_suggestion, pairing) | ○ | 作成の経路 |
| feedback | enum(none, accepted, rejected) | ○ | 提案への反応。既定は none |
| feedback_note | string | - | 却下の理由など |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| WRD-UC-01 | 世帯を作り、世帯メンバー（ログインしない家族を含む）を登録・一覧・編集・削除する | MVP | `submodules/wardrowbe/README.md`（Features: Family support） |
| WRD-UC-02 | 衣服を属性付きで登録する（画像は任意） | MVP | `submodules/wardrowbe/README.md`（Features）、Issue #19 |
| WRD-UC-03 | 衣服を一覧・検索する（持ち主・種類・季節・場面・洗濯ステータス・所持状態・色・名前で絞り込み、着用回数・最後に着た日で並べ替え） | MVP | `submodules/wardrowbe/README.md`（Screenshots: Grid View） |
| WRD-UC-04 | 衣服の詳細を取得し、属性を編集する | MVP | `submodules/wardrowbe/README.md`（Screenshots: Item Details） |
| WRD-UC-05 | 手放した衣服をアーカイブし、必要なら元に戻す。誤登録は削除する | MVP | https://wardrowbe.com/features （Decide what stays。採用は LifePipe の判断） |
| WRD-UC-06 | 衣服の画像をアップロードして保存し、一覧に出す画像を選ぶ | MVP | `submodules/wardrowbe/README.md`（Features: Photo-based wardrobe）、Issue #19 |
| WRD-UC-07 | 衣服の画像を有効期限付き URL で取得する | MVP | `submodules/wardrowbe/docs/forward-auth.md`（署名付きの画像リンク） |
| WRD-UC-08 | 着た服を日付・メンバー単位で記録する（評価・メモは任意） | MVP | `submodules/wardrowbe/README.md`（Features: Wear tracking）、Issue #19 |
| WRD-UC-09 | 期間を指定して着用履歴を見る（カレンダー表示用） | MVP | `submodules/wardrowbe/README.md`（Screenshots: History Calendar） |
| WRD-UC-10 | 誤った着用記録を修正・削除する | MVP | `submodules/wardrowbe/README.md`（Features: Wear tracking） |
| WRD-UC-11 | 洗濯ステータスを変更する（要洗濯にする・洗濯に出す・洗濯済みにする）。複数着をまとめて変更できる | MVP | `submodules/wardrowbe/README.md`（Screenshots: Wash Tracking）、Issue #19 |
| WRD-UC-12 | 要洗濯・洗濯中の服を一覧する | MVP | `submodules/wardrowbe/README.md`（Screenshots: Wash Tracking） |
| WRD-UC-13 | 日付・気温・降水確率・場面を条件に、当日着られる服を役割別に取得する | MVP | `submodules/wardrowbe/README.md`（Features: Smart recommendations）、`README.md`（4.1）、Issue #19 |
| WRD-UC-14 | 購入の振り分けから衣類の品目を受け取り、衣服として登録する | MVP | `README.md`（4.2） |
| WRD-UC-15 | 画像処理ジョブの状態を取得する | 後回し | `submodules/wardrowbe/README.md`（Architecture: Background Worker） |
| WRD-UC-16 | 画像から AI で種類・色・柄・素材・スタイル・フォーマル度を推定し、利用者が確認してから属性に反映する | 後回し | `submodules/wardrowbe/README.md`（AI Configuration）、https://wardrowbe.com |
| WRD-UC-17 | 画像の背景を除去し、加工後の画像を保存する | 後回し | `submodules/wardrowbe/README.md`（Background Removal） |
| WRD-UC-18 | 天気・場面・メモ・好みをもとに AI がコーディネートを提案し、採用・却下の反応を記録する | 後回し | `submodules/wardrowbe/README.md`（Features: Smart recommendations）、https://wardrowbe.com/features |
| WRD-UC-19 | 1着を起点に、合う服の組み合わせ（ペアリング）を作る | 後回し | `submodules/wardrowbe/README.md`（Screenshots: Pairings）、https://wardrowbe.com |
| WRD-UC-20 | コーディネートを手動で作り、保存・一覧・削除する | 後回し | `submodules/wardrowbe/README.md`（Running without internal AI） |
| WRD-UC-21 | よく着る服・着ていない服・色の分布を集計する | 後回し | `submodules/wardrowbe/README.md`（Features: Analytics） |

## 業務ルール

| ID | ルール | 出典 |
| --- | --- | --- |
| WRD-BR-01 | 衣服はちょうど1人の世帯メンバーが持つ。同じ世帯のメンバーは互いの衣服を閲覧・編集できる。別の世帯の衣服・着用記録・画像には触れられない（404 を返す） | `submodules/wardrowbe/README.md`（Features: Family support）。権限の細かさは LifePipe で定義する |
| WRD-BR-02 | 洗濯ステータスは clean（着られる）・needs_wash（要洗濯）・in_laundry（洗濯中）の3つで、遷移は次のとおり。(1) clean → needs_wash: 着用記録で wears_since_wash が wears_before_wash に達したとき（trigger=wear_threshold）、または利用者が手動で要洗濯にしたとき（trigger=manual）。(2) clean / needs_wash → in_laundry: 洗濯に出したとき（manual）。(3) needs_wash / in_laundry → clean: 洗濯済みにしたとき（trigger=washed）。wears_since_wash を 0 にし、last_washed_at を現在時刻にする。(4) clean → clean の洗濯済み操作も受け付け、同じ処理をする。(5) in_laundry → needs_wash は手動でだけ行える。どの遷移でも WashLog を1件残す | `submodules/wardrowbe/README.md`（Screenshots: Wash Tracking）。状態と遷移は LifePipe で定義する |
| WRD-BR-03 | wears_before_wash が 0 の服（既定では shoes・accessory・bag）は洗濯管理の対象外とし、wash_status は常に clean で、洗濯ステータスの変更は 422 で拒否する。wears_before_wash を 0 から 1 以上に変えたら wears_since_wash を 0 から数え直す | LifePipe で定義する |
| WRD-BR-04 | wears_before_wash を省略して登録したときの既定値は category で決める: innerwear 1、top 2、one_piece 2、bottom 5、outerwear 10、other 3、shoes・accessory・bag 0。値は 0〜99 の整数 | LifePipe で定義する |
| WRD-BR-05 | 着用記録1件を作ると、含まれる服ごとに wear_count と wears_since_wash を 1 増やし、last_worn_on を worn_on と既存値の新しいほうにする。その結果 wears_since_wash ≥ wears_before_wash（かつ wears_before_wash ≥ 1）になった clean の服は needs_wash に変える | `submodules/wardrowbe/README.md`（Features: Wear tracking）。計算方法は LifePipe で定義する |
| WRD-BR-06 | 同じ服を同じメンバーが同じ日に複数回記録しても、着用回数は1回と数える。同じ日付の既存記録にすでに含まれる服は、新しい記録では数えない | LifePipe で定義する |
| WRD-BR-07 | worn_on が last_washed_at の日付より前の着用記録は、wear_count だけを増やし、wears_since_wash は増やさない（洗濯前の着用を後から記録した場合） | LifePipe で定義する |
| WRD-BR-08 | 着用記録を削除・修正して服が外れたら、wear_count を 1 減らし、その日が last_washed_at より後なら wears_since_wash も 1 減らす（0 未満にしない）。last_worn_on は残りの記録から計算し直す。洗濯ステータスは自動では戻さない | LifePipe で定義する |
| WRD-BR-09 | in_laundry の服とアーカイブ済みの服は着用記録に含められない（409 を返す）。needs_wash の服は記録でき、ステータスは needs_wash のまま | LifePipe で定義する |
| WRD-BR-10 | worn_on は未来の日付にできない（422）。item_ids は1件以上で、すべて同じ世帯のものでなければならない | LifePipe で定義する |
| WRD-BR-11 | 着られる服の取得（WRD-UC-13）では、status=active かつ wash_status=clean の服だけを候補にする。needs_wash・in_laundry・archived は除く | `README.md`（4.1: 着用可能リスト）、Issue #19 |
| WRD-BR-12 | 気温の判定: 呼び出し側が当日の最高気温 temp_max と最低気温 temp_min（℃）を渡す。服に min_temp・max_temp があればそれを使い、temp_max ≤ max_temp かつ temp_min ≥ min_temp（片方だけなら片方）を満たす服を候補にする。どちらも無い服は、temp_max から下の「気温帯と厚さの対応表」で決まる warmth の範囲に入るものを候補にする。outerwear は temp_max ではなく temp_min で帯を決める | `submodules/wardrowbe/README.md`（Features: Smart recommendations）。基準値は LifePipe で定義する |
| WRD-BR-13 | 季節の判定: 下の対応表で気温帯から当日の季節を決め、seasons が空の服、または当日の季節を含む服だけを候補にする。暦の月は使わない | LifePipe で定義する |
| WRD-BR-14 | アウターの要否: temp_min が 15℃ 未満、または降水確率 precipitation_probability が 50% 以上なら outerwear を必要とする。降水確率が 50% 以上のときは water_resistant=true の outerwear を先に並べる。どちらにも当てはまらなければ outerwear の候補は返すが「不要」と示す | `README.md`（4.1: 気温・降水確率） |
| WRD-BR-15 | 場面の判定: 呼び出し側は予定から場面を1つ決めて occasion として渡す（予定が無く在宅なら home、外出の予定があり場面が分からなければ casual）。occasions にその場面を含む服、occasions が空で場面が casual か home の服を候補にする。min_formality を渡したときは formality がそれ以上の服に絞る（formality 未設定は条件に合わないとみなす） | `README.md`（4.1: 在宅か外出か）、`submodules/wardrowbe/README.md`（Features: occasion）。場面の分け方は LifePipe で定義する |
| WRD-BR-16 | 着られる服の結果は役割ごとに分ける: top（top と innerwear）、bottom、one_piece、outerwear、shoes、accessory（accessory・bag・other）。各役割の中は last_worn_on の古い順（未着用を先）に並べ、同じなら wear_count の少ない順にする。服を偏りなく回すため。1日の服装は「top と bottom」または「one_piece」に、shoes と必要なら outerwear を加えて組む | https://wardrowbe.com/features （服装の組み方）、`submodules/wardrowbe/README.md`（Features: Analytics） |
| WRD-BR-17 | member_id を指定したときはその人の服だけを返す。指定しなければ世帯全員の服を返す | LifePipe で定義する |
| WRD-BR-18 | 画像は jpeg・png・webp を受け付け、1枚 50MB 以下とする。超えたら 413、形式が違えば 415。アップロードは同期で元画像（original）を保存し、保存できた時点で応答する。衣服1着の画像は 10 枚まで | `docs/local-stack.md` と `compose.yaml`（Wardrowbe の nginx の上限 50M）。枚数は LifePipe で定義する |
| WRD-BR-19 | 画像の URL は取得のたびに有効期限付きで発行し、期限は 1 時間とする。保存先のキーやファイルパスは API で返さない | `submodules/wardrowbe/docs/forward-auth.md`（署名付きの画像リンクは期限まで有効）。期限は LifePipe で定義する |
| WRD-BR-20 | サムネイル作成・背景除去・AI による属性推定は時間がかかるため、非同期の画像処理ジョブ（ImageJob）で行う。ジョブは pending → running → succeeded / failed と進み、failed は最大 3 回まで再試行する。ジョブの結果は元画像や手入力の属性を上書きしない（AI の推定は提案として持ち、利用者が承認したときだけ属性に反映する）。MVP ではジョブを作らないが、API は ImageJob と kind 付きの ItemImage を前提にし、後から機能を足しても互換を保つ | `submodules/wardrowbe/README.md`（Architecture、Background Removal、AI Configuration）、`compose.yaml`（worker・image-worker）、https://wardrowbe.com （登録前に推定結果を確認する） |
| WRD-BR-21 | AI と背景除去が使えない設定でも、衣服の登録・編集・画像の保存・着用記録・洗濯管理・着られる服の取得は動く。使えない機能を呼んだら 501 を返す | `submodules/wardrowbe/README.md`（Running without internal AI、Background Removal） |
| WRD-BR-22 | アーカイブした服は一覧の既定の絞り込み（status=active）から外れ、着用履歴と集計には残る。元に戻すと status=active、archived_at を空にし、洗濯ステータスと回数は保つ。削除は着用記録から参照されていない服だけに許し、参照されていれば 409 を返してアーカイブを促す | https://wardrowbe.com/features （手放した服はアーカイブし、後で戻せる）。削除の条件は LifePipe で定義する |
| WRD-BR-23 | 購入の振り分けから登録した服は source=purchase、wash_status=clean、wears_since_wash=0 とする。name と category は必須で、category を判断できない品目は other で登録する。同じ購入から同じ品目を二重に登録しないよう、呼び出し側は冪等キー（Idempotency-Key ヘッダー）を付け、wardrobe は 24 時間同じキーの再送に同じ結果を返す | `README.md`（4.2）。冪等性は LifePipe で定義する |
| WRD-BR-24 | 着用記録の rating は 1〜5、Item の warmth と formality は 1〜5、min_temp ≤ max_temp でなければならない（違反は 422） | LifePipe で定義する |
| WRD-BR-25 | ログやエラーメッセージに衣服の名前・メモ・画像の内容を出さない | `AGENTS.md` |

### 気温帯と厚さの対応表（WRD-BR-12・WRD-BR-13）

基準の気温は、outerwear 以外は temp_max、outerwear は temp_min とする。境界の値は上の帯に含める（例: 25.0℃ は「25℃ 以上」）。

| 基準の気温 | 候補にする warmth | 当日の季節 |
| --- | --- | --- |
| 25℃ 以上 | 1〜2 | summer |
| 20℃ 以上 25℃ 未満 | 1〜3 | spring・autumn・summer |
| 15℃ 以上 20℃ 未満 | 2〜4 | spring・autumn |
| 10℃ 以上 15℃ 未満 | 3〜5 | spring・autumn・winter |
| 10℃ 未満 | 4〜5 | winter |

## LifePipe のワークフローとの関係

| ワークフロー | wardrobe が提供するもの |
| --- | --- |
| get_morning_briefing | 着られる服の取得（WRD-UC-13）。ゲートウェイは気象 API の最高・最低気温と降水確率、Google Calendar の予定から決めた場面を渡し、役割別の候補を受け取る。ゲートウェイは各役割の先頭を組み合わせて1パターンに確定する。服装を確定したら、その日の着用記録（WRD-UC-08）を登録できる |
| ingest_purchase | 衣類・ファッション小物の品目を衣服として登録する（WRD-UC-14）。画像があれば続けてアップロードする（WRD-UC-06） |
| prepare_outing | 直接は提供しない。要洗濯の一覧（WRD-UC-12）は、将来クリーニングに出す外出タスクの材料になる |

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| households | 取得・更新 | WRD-UC-01 | `GET/PATCH /households/{household_id}`。作成は利用開始時に行う |
| households/{id}/members | 一覧・作成・取得・更新・削除 | WRD-UC-01 | 衣服を持つメンバーは削除できない（409） |
| items | 一覧（フィルタ: owner_member_id、category、season、occasion、wash_status、status（既定 active）、color、q（名前の部分一致）。並べ替え: last_worn_on、wear_count、created_at。ページング: cursor・limit） | WRD-UC-03, WRD-UC-12 | 要洗濯の一覧は `wash_status=needs_wash,in_laundry` で取る |
| items | 作成 | WRD-UC-02, WRD-UC-14 | 購入からの登録は `source=purchase` と Idempotency-Key ヘッダーを付ける |
| items/{item_id} | 取得・更新（PATCH）・削除 | WRD-UC-04, WRD-UC-05 | 回数と洗濯関係の読み取り専用項目は PATCH で変えられない |
| items/{item_id}/archive | アーカイブ（POST）・元に戻す（DELETE） | WRD-UC-05 | |
| items/{item_id}/images | 一覧・アップロード（multipart/form-data） | WRD-UC-06, WRD-UC-07 | 応答に有効期限付きの url を含める |
| items/{item_id}/images/{image_id} | 取得・削除 | WRD-UC-06, WRD-UC-07 | primary の画像を消したら primary_image_id を空にする |
| items/{item_id}/primary-image | 設定（PUT） | WRD-UC-06 | |
| items/{item_id}/wash-status | 変更（POST、body: action=mark_dirty / send_to_laundry / mark_washed） | WRD-UC-11 | 遷移は WRD-BR-02 |
| wash-status:batch | 一括変更（POST、body: item_ids と action） | WRD-UC-11 | 1件でも遷移できなければ全体を 409 にする |
| items/{item_id}/wash-logs | 一覧 | WRD-UC-11 | |
| wear-logs | 一覧（フィルタ: member_id、item_id、from、to）・作成 | WRD-UC-08, WRD-UC-09 | カレンダー表示は from・to で期間を取る |
| wear-logs/{wear_log_id} | 取得・更新・削除 | WRD-UC-10 | 回数の戻し方は WRD-BR-08 |
| available-items | 取得（GET、クエリ: date、temp_max、temp_min、precipitation_probability、occasion、min_formality、member_id） | WRD-UC-13 | 応答は役割ごとの配列と、outerwear が必要かどうか（WRD-BR-11〜17） |
| image-jobs/{job_id} | 取得 | WRD-UC-15 | 後回し |
| items/{item_id}/images/{image_id}/background-removal | ジョブ作成（POST、202） | WRD-UC-17 | 後回し。使えない設定では 501 |
| items/{item_id}/images/{image_id}/tagging | ジョブ作成（POST、202）・推定結果の承認（POST .../accept） | WRD-UC-16 | 後回し |
| outfits | 一覧・作成・取得・更新・削除 | WRD-UC-20 | 後回し |
| outfit-suggestions | 生成（POST、条件は available-items と同じ）・反応の記録（POST .../feedback） | WRD-UC-18 | 後回し。AI の応答待ちが長いため非同期にする |
| items/{item_id}/pairings | 生成（POST） | WRD-UC-19 | 後回し |
| stats | 取得（期間別の着用回数、未着用の服、色の分布） | WRD-UC-21 | 後回し |

## 対象外

| 機能 | 理由 |
| --- | --- |
| AI による属性推定・コーディネート提案・ペアリング（MVP では） | Issue #19 で、登録・着用・着られる服の取得の後に作ると決めている。データの項目と API の形だけ先に用意する |
| 画像の背景除去（MVP では） | 非同期ジョブと実行基盤が必要で、Go で作るか別コンポーネントにするかを ADR #14 で決める |
| 天気の取得・位置情報の保持 | ゲートウェイが気象 API から取得して条件として渡すため、wardrobe は持たない |
| 通知チャネル（ntfy・Mattermost・メール）と定時の送信 | 朝の通知は get_morning_briefing が行う |
| サインイン（開発用ログイン・OIDC・forward-auth）とアカウントの結び付け | LifePipe 共通の認証（edge）が担う |
| 多言語の画面文言 | 画面はフロントエンド（Issue #26）の責務 |
| 買う前の照合、複数着の一括撮影、不足アイテムの報告、着用確認、衣服の見直し、共有、試着プレビュー | 参考元でもクラウド版だけの機能で、セルフホスト版に無い |
| Wardrowbe の既存データの取り込み | Issue #19 で、必要になったら作る任意の作業としている |

## 出典

- `submodules/wardrowbe/README.md`
- `submodules/wardrowbe/docs/forward-auth.md`
- `submodules/wardrowbe/docs/sign-in-identities.md`
- `submodules/wardrowbe/k8s/README.md`
- `compose.yaml`（LifePipe）
- `docs/local-stack.md`（LifePipe）
- `README.md`（LifePipe、4.1・4.2 と対象サービス一覧）
- `AGENTS.md`（LifePipe）
- https://wardrowbe.com
- https://wardrowbe.com/features
- https://github.com/UtakataKyosui/LifePipe/issues/19
