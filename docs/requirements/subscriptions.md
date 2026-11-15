# subscriptions: 固定費・サブスクリプション管理 の要件

参考元: Wallos（GPL-3.0）。ソースコードは参照していない。

## 責務

subscriptions サービスは、定期的に支払いが発生する契約（動画配信・ソフトウェア・通信費・保険料などの固定費）の台帳を持つ。

持つデータ:

- サブスクリプション本体（名前、金額、通貨、支払いサイクル、開始日、次回支払日、更新方法、有効・停止の状態、メモ、URL）
- サブスクリプションの分類に使うマスタ（カテゴリ。後回しで支払い方法・支払者・フォルダ）
- 支払い済みの記録（支払い済みにした日と金額）
- 後回し: 通知設定、利用者ごとの表示設定（基準通貨・予算）、為替レートの取得結果

持たないデータ:

- 実際の口座残高・カード明細・家計簿の取引。銀行やカード会社とは連携しない。
- 購入した物品（inventory・pantry・wardrobe の責務）。単発の買い物は扱わない。
- 予定・タスク（tasks の責務）。支払日をカレンダー予定として複製しない。
- アカウント情報。利用者は共通の ID 基盤（OIDC）の subject で識別し、パスワードや API キーは持たない。

他ドメインとの境界:

- `life-mcp` は subscriptions の更新予定を読み、`get_morning_briefing` に載せる。subscriptions から他ドメインへは書き込まない。
- レシートの品目は subscriptions に振り分けない。定期契約の登録は利用者が明示的に行う。

## 参考元の構成

- 主な機能のまとまり: サブスクリプションの登録・一覧（並び替え・絞り込み・一括操作）、カテゴリ・通貨・支払い方法・世帯メンバーの設定、ダッシュボード（今月の支払額・直近の支払い予定）、カレンダー表示と iCalendar 配信、統計（月額・年額の合計、予算との比較、推移）、通知（支払い前のリマインド、解約日のリマインド）、AI による節約提案、CSV/JSON エクスポート、データベースのバックアップ・復元。出典: `submodules/Wallos/README.md`、https://wallosapp.com/
- データの保存先: SQLite の単一ファイル。ロゴ画像はファイルとして保存する。出典: `submodules/Wallos/README.md`
- 定期ジョブ: cron で次回支払日の更新（毎日）、為替レートの更新（毎日）、支払い通知と解約通知の送信（毎日）、年額合計の記録（毎週）、AI 提案の生成（毎週・毎月）を動かす。タイムゾーンはコンテナの `TZ` に従う。出典: `submodules/Wallos/README.md`、`submodules/Wallos/CHANGELOG.md`
- 外部依存: 為替レートの提供元（Fixer、apilayer、frankfurter.dev、allratestoday.com）、通知先（メール、Discord、Pushover、Telegram、Gotify、ntfy、Webhook、Mattermost、プッシュ通知ほか）、AI（ChatGPT、Gemini、OpenRouter、Ollama、OpenAI 互換 API）、ロゴ検索。出典: `submodules/Wallos/README.md`、`submodules/Wallos/CHANGELOG.md`
- 認証方式: ユーザー名とパスワード（任意で TOTP の 2 要素認証）、OIDC。API は利用者ごとの API キーで呼ぶ。出典: `submodules/Wallos/README.md`、`submodules/Wallos/CHANGELOG.md`
- マルチユーザー/グループの単位: データは利用者（アカウント）ごとに分かれる。1 つのアカウントの中に「世帯メンバー」を登録し、サブスクリプションの支払者として割り当てる。最初のアカウントが管理者になる。出典: `submodules/Wallos/README.md`、`submodules/Wallos/CHANGELOG.md`

## エンティティ

### Subscription（サブスクリプション）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。サーバーが採番する。 |
| owner_id | string | 必須 | 所有者。OIDC の subject。リクエストの認証情報から決まり、クライアントは指定しない。 |
| name | string | 必須 | サービス名。1〜100 文字。例: 「架空動画プラス」 |
| amount | string | 必須 | 1 回の支払額。10 進数の文字列（例: `"1480"`、`"9.99"`）。0 以上。小数の桁数は通貨の補助単位の桁数以下。 |
| currency | string | 必須 | ISO 4217 の通貨コード（例: `JPY`、`USD`）。 |
| cycle_unit | enum(day, week, month, year) | 必須 | 支払いサイクルの単位。 |
| cycle_interval | integer | 必須 | サイクルの間隔。1〜366。例: `cycle_unit=month, cycle_interval=3` は 3 か月ごと。 |
| start_date | date | 必須 | 契約の開始日で、支払日の起点。省略時はサーバーの当日（利用者のタイムゾーン）を入れる。 |
| next_payment_date | date | 必須 | 次回支払日。省略時は SUB-BR-04 で計算する。明示した場合はその値を使う。 |
| anchor_date | date | 必須 | 支払日の列の起点（SUB-BR-02、SUB-BR-05）。既定は `start_date`。`next_payment_date` を列から外れた日付で明示するとその日付に変わる。読み取り専用。 |
| renewal_type | enum(auto, manual) | 必須 | 更新方法。`auto` は支払日を過ぎると自動で次の支払日へ進む。`manual` は利用者が支払い済みにするまで進まない。既定値 `auto`。 |
| status | enum(active, inactive) | 必須 | 有効・停止。停止中は更新予定・合計額・通知の対象外。既定値 `active`。 |
| end_date | date | 任意 | 契約の終了日（解約予定日）。この日より後の支払日は発生しない。 |
| category_id | 参照(Category) | 任意 | カテゴリ。未指定は「未分類」として扱う。 |
| url | string | 任意 | 契約の管理ページなどの URL。http または https。 |
| notes | string | 任意 | メモ。Markdown を許す。最大 2000 文字。 |
| payment_method_id | 参照(PaymentMethod) | 任意 | 支払い方法（後回し）。 |
| payer_ids | array<参照(HouseholdMember)> | 任意 | 支払者（後回し）。複数可。 |
| folder_id | 参照(Folder) | 任意 | グループ分け用のフォルダ（後回し）。 |
| replaced_by_id | 参照(Subscription) | 任意 | 停止したサブスクリプションの乗り換え先（後回し）。節約額の計算に使う。 |
| notify | boolean | 任意 | 支払い前に通知するか（後回し）。既定値 false。 |
| notify_days_before | integer | 任意 | 何日前に通知するか（後回し）。0〜180。0 は支払日当日。未指定は利用者の既定値。 |
| last_paid_on | date | 任意 | 最後に支払い済みにした支払日。読み取り専用。 |
| created_at | date-time | 必須 | 作成日時。読み取り専用。 |
| updated_at | date-time | 必須 | 更新日時。読み取り専用。 |

### Category（カテゴリ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。 |
| owner_id | string | 必須 | 所有者。OIDC の subject。 |
| name | string | 必須 | カテゴリ名。1〜50 文字。所有者の中で重複不可。例: 「動画配信」「通信」 |
| sort_order | integer | 必須 | 表示順。小さい順に並べる。省略時は末尾。 |
| created_at | date-time | 必須 | 作成日時。 |
| updated_at | date-time | 必須 | 更新日時。 |

### Payment（支払い記録）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。 |
| subscription_id | 参照(Subscription) | 必須 | 対象のサブスクリプション。 |
| due_date | date | 必須 | 支払い済みにした支払日（その時点の next_payment_date）。 |
| amount | string | 必須 | 支払額。既定はその時点の Subscription.amount。 |
| currency | string | 必須 | 通貨コード。既定はその時点の Subscription.currency。 |
| paid_at | date-time | 必須 | 支払い済みにした日時。 |
| created_at | date-time | 必須 | 作成日時。 |

### UpcomingPayment（更新予定。計算結果で保存しない）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| subscription_id | 参照(Subscription) | 必須 | 対象のサブスクリプション。 |
| name | string | 必須 | サブスクリプション名。 |
| due_date | date | 必須 | 支払日。 |
| amount | string | 必須 | 支払額。 |
| currency | string | 必須 | 通貨コード。 |
| category_id | 参照(Category) | 任意 | カテゴリ。 |
| renewal_type | enum(auto, manual) | 必須 | 更新方法。manual の予定は利用者の操作が必要なことを示す。 |
| overdue | boolean | 必須 | 支払日が当日より前で、まだ支払い済みにしていない（manual のみ true になりうる）。 |

### UserSettings（利用者設定。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| owner_id | string | 必須 | 所有者。OIDC の subject。 |
| timezone | string | 必須 | IANA タイムゾーン名（例: `Asia/Tokyo`）。「当日」の判定に使う。既定値はサービスの設定値。 |
| main_currency | string | 必須 | 合計額を表示する基準通貨（ISO 4217）。 |
| monthly_budget | string | 任意 | 月の予算（基準通貨）。空または 0 は予算なし。 |
| default_notify_days_before | integer | 任意 | 通知の既定日数。0〜180。 |
| updated_at | date-time | 必須 | 更新日時。 |

### PaymentMethod（支払い方法。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。 |
| owner_id | string | 必須 | 所有者。 |
| name | string | 必須 | 名前。例: 「架空カード」「口座振替」。カード番号などの秘密情報は持たない。 |
| enabled | boolean | 必須 | 選択肢に出すか。 |
| sort_order | integer | 必須 | 表示順。 |
| created_at | date-time | 必須 | 作成日時。 |
| updated_at | date-time | 必須 | 更新日時。 |

### HouseholdMember（世帯メンバー。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。 |
| owner_id | string | 必須 | 所有者。 |
| name | string | 必須 | 表示名。 |
| email | string | 任意 | 通知先のメールアドレス。 |
| created_at | date-time | 必須 | 作成日時。 |
| updated_at | date-time | 必須 | 更新日時。 |

### Folder（フォルダ。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 一意な ID（UUID）。 |
| owner_id | string | 必須 | 所有者。 |
| name | string | 必須 | フォルダ名。 |
| color | string | 任意 | 表示色（`#RRGGBB`）。 |
| created_at | date-time | 必須 | 作成日時。 |
| updated_at | date-time | 必須 | 更新日時。 |

### ExchangeRate（為替レート。後回し）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| base_currency | string | 必須 | 基準通貨。 |
| quote_currency | string | 必須 | 換算先の通貨。 |
| rate | string | 必須 | 基準通貨 1 単位あたりの換算先通貨の量。10 進数の文字列。 |
| fetched_on | date | 必須 | 取得日。 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| SUB-UC-01 | サブスクリプションを登録する（名前、金額、通貨、支払いサイクル、開始日、次回支払日、カテゴリ、更新方法、URL、メモ）。次回支払日を省略すると自動で計算する。 | MVP | `submodules/Wallos/README.md`（Subscription Management）、`submodules/Wallos/CHANGELOG.md`（start date、auto fill the next payment date、manual/automatic renewals） |
| SUB-UC-02 | サブスクリプションの一覧を取得する。状態（有効・停止）、カテゴリ、更新方法で絞り込み、名前・次回支払日・金額で並べ替える。 | MVP | `submodules/Wallos/README.md`（Sorting Options）、`submodules/Wallos/CHANGELOG.md`（filter/sort by renew type、hide disabled subscriptions） |
| SUB-UC-03 | サブスクリプションを 1 件取得する。 | MVP | `submodules/Wallos/README.md`（Subscription Management） |
| SUB-UC-04 | サブスクリプションを更新する。サイクルや開始日を変えたときは次回支払日を計算し直せる。 | MVP | `submodules/Wallos/README.md`（Subscription Management）、`submodules/Wallos/CHANGELOG.md`（auto fill the next payment date） |
| SUB-UC-05 | サブスクリプションを削除する。 | MVP | `submodules/Wallos/README.md`（Subscription Management） |
| SUB-UC-06 | サブスクリプションを停止・再開する（解約したが記録は残す）。 | MVP | `submodules/Wallos/CHANGELOG.md`（disabled/inactive subscriptions） |
| SUB-UC-07 | 次回支払日を計算する（保存せずに、サイクルと開始日から候補を返す）。 | MVP | `submodules/Wallos/CHANGELOG.md`（auto fill the next payment date） |
| SUB-UC-08 | 期間を指定して更新予定（支払日の一覧）を取得する。朝のブリーフィングで「数日以内に引き落としがある固定費」を出すのに使う。 | MVP | `submodules/Wallos/README.md`（never miss a due date）、`submodules/Wallos/CHANGELOG.md`（dashboard upcoming payment、calendar） |
| SUB-UC-09 | 自動更新のサブスクリプションの次回支払日を、支払日を過ぎたら次の支払日へ進める（毎日の定期処理）。 | MVP | `submodules/Wallos/README.md`（updatenextpayment の定期ジョブ）、`submodules/Wallos/CHANGELOG.md`（don't update next payment date for disabled subscriptions） |
| SUB-UC-10 | カテゴリを登録・一覧・更新・削除・並べ替えする。 | MVP | `submodules/Wallos/README.md`（Category Management）、`submodules/Wallos/CHANGELOG.md`（sort categories by the order column） |
| SUB-UC-11 | 支払いを支払い済みにする・取り消す。手動更新のサブスクリプションはこれで次回支払日が進む。 | 後回し | `submodules/Wallos/CHANGELOG.md`（5.11.0 mark/unmark paid） |
| SUB-UC-12 | 月額・年額の合計を、基準通貨に換算して取得する。 | 後回し | `submodules/Wallos/README.md`（Statistics、Currency Conversion）、`submodules/Wallos/CHANGELOG.md`（api endpoint to calculate monthly cost） |
| SUB-UC-13 | 通貨と基準通貨を設定し、為替レートを定期的に取得する。 | 後回し | `submodules/Wallos/README.md`（Multi-Currency support、Currency Conversion、Usage） |
| SUB-UC-14 | 支払い方法を登録・一覧・更新・削除する。 | 後回し | `submodules/Wallos/CHANGELOG.md`（payment methods、allow sorting payment methods） |
| SUB-UC-15 | 世帯メンバーを登録し、サブスクリプションの支払者に割り当てる（複数可）。 | 後回し | `submodules/Wallos/README.md`（Usage: members of your household）、`submodules/Wallos/CHANGELOG.md`（several payers per subscription） |
| SUB-UC-16 | 支払日の N 日前に通知する。解約予定日の前に通知する。 | 後回し | `submodules/Wallos/README.md`（Notifications）、`submodules/Wallos/CHANGELOG.md`（personalized notification times、cancelation reminders、up to 180 days） |
| SUB-UC-17 | 月の予算を設定し、予算との比較を取得する。 | 後回し | `submodules/Wallos/CHANGELOG.md`（monthly budget field and statistics、payment-period budgeting） |
| SUB-UC-18 | 統計（カテゴリ別・支払者別の内訳、月額合計の推移、停止したサブスクリプションによる節約額）を取得する。 | 後回し | `submodules/Wallos/README.md`（Statistics）、`submodules/Wallos/CHANGELOG.md`（total monthly cost trend graph、stats about inactive subscriptions、replacement for disabled subscriptions） |
| SUB-UC-19 | フォルダでサブスクリプションをまとめ、フォルダごとの合計を出す。 | 後回し | `submodules/Wallos/CHANGELOG.md`（5.11.0 colored folders） |
| SUB-UC-20 | 更新予定を iCalendar で配信する。 | 後回し | `submodules/Wallos/CHANGELOG.md`（icalendar subscription、RFC 5545） |
| SUB-UC-21 | サブスクリプションを CSV・JSON でエクスポートする。 | 後回し | `submodules/Wallos/CHANGELOG.md`（export subscriptions as csv/json） |
| SUB-UC-22 | 複数のサブスクリプションをまとめて削除する・カテゴリを変える。 | 後回し | `submodules/Wallos/CHANGELOG.md`（bulk delete and set-category） |

## 業務ルール

日付はすべて暦日（`date`）で扱い、「当日」は利用者のタイムゾーン（UserSettings.timezone。未設定ならサービスの既定タイムゾーン）で決める。

| ID | ルール | 出典 |
| --- | --- | --- |
| SUB-BR-01 | 支払いサイクルは単位（`day`・`week`・`month`・`year`）と間隔（1〜366 の整数）の組で表す。1 サイクルの長さは、`day` は間隔×1 日、`week` は間隔×7 日、`month` は間隔×1 か月、`year` は間隔×12 か月。範囲外の間隔は 400 で拒否する。 | `submodules/Wallos/CHANGELOG.md`（frequency is now up to 366、billing cycle） |
| SUB-BR-02 | 支払日の列は起点（`anchor_date`）から作る。k 回目（k = 0, 1, 2, …）の支払日 `D(k)` は次のとおり。`day`・`week`: `anchor_date + k × 1 サイクルの日数`。`month`・`year`: `anchor_date` に `k × 1 サイクルの月数` を足した年月の、`anchor_date` と同じ日。`anchor_date` の既定は `start_date`。その年月にその日がない場合は、その月の末日にする。 | `submodules/Wallos/CHANGELOG.md`（start date、calendar occurrences to respect subscription start date）。月末日の扱いは LifePipe の決定。 |
| SUB-BR-03 | 月末日の扱いの例: 開始日 1 月 31 日・毎月 → 2 月 28 日（うるう年は 29 日）、3 月 31 日、4 月 30 日、5 月 31 日。開始日 2024 年 2 月 29 日・毎年 → 2025 年 2 月 28 日、2028 年 2 月 29 日。開始日 8 月 31 日・3 か月ごと → 11 月 30 日、2 月 28 日（または 29 日）、5 月 31 日。前回の支払日に足し込まず、毎回起点から計算するため、一度末日に丸めても後の月で日付が戻る。 | LifePipe の決定（SUB-BR-02 の具体例） |
| SUB-BR-04 | 次回支払日の計算（SUB-UC-07、登録時に省略した場合）は、`D(k) >= 基準日` を満たす最小の `D(k)` を返す。基準日は既定で当日。開始日が基準日より後なら開始日そのものが次回支払日になる。基準日と同じ日の支払日は「次回」に含める。 | `submodules/Wallos/CHANGELOG.md`（auto fill the next payment date、include todays subscriptions on amount due this month） |
| SUB-BR-05 | 登録・更新で `next_payment_date` を明示した場合はその値を保存する。開始日より前の日付は 400 で拒否する。明示した日付が支払日の列（SUB-BR-02）に乗っていない場合も受け付け、以後の進め方はその日付を新しい起点として SUB-BR-02 を適用する（`start_date` は契約開始日として残し、起点は内部で `anchor_date` として持つ）。 | LifePipe の決定 |
| SUB-BR-06 | サイクル（単位・間隔）または開始日を更新したとき、リクエストに `next_payment_date` がなければ SUB-BR-04 で計算し直す。金額・名前などそれ以外の更新では次回支払日を変えない。 | `submodules/Wallos/CHANGELOG.md`（auto fill the next payment date）。LifePipe の決定。 |
| SUB-BR-07 | 自動更新（`renewal_type=auto`）かつ有効（`status=active`）のサブスクリプションは、毎日の定期処理で `next_payment_date < 当日` のとき、`D(k) >= 当日` を満たす最小の `D(k)` へ進める。複数サイクル分遅れていても 1 回で追いつく。定期処理は冪等にし、同じ日に何度動かしても結果は同じ。一覧・更新予定の取得時にも同じ計算を適用し、定期処理の前でも過去の日付を返さない。 | `submodules/Wallos/README.md`（updatenextpayment の毎日のジョブ） |
| SUB-BR-08 | 手動更新（`renewal_type=manual`）のサブスクリプションは、支払日を過ぎても次回支払日を自動で進めない。更新予定では `overdue=true` として返し、支払い済みにした時点（SUB-UC-11）で次の支払日へ進める。 | `submodules/Wallos/CHANGELOG.md`（manual/automatic renewals、mark/unmark paid） |
| SUB-BR-09 | 停止中（`status=inactive`）のサブスクリプションは、次回支払日を進めず、更新予定・合計額・通知の対象にしない。再開したときは SUB-BR-04 で当日以降の次回支払日を計算し直す。 | `submodules/Wallos/CHANGELOG.md`（don't update next payment date for disabled subscriptions、subscription progress for disabled subscriptions） |
| SUB-BR-10 | 終了日（`end_date`）があるサブスクリプションは、終了日より後の支払日を生成しない。終了日を過ぎ、残る支払日がなくなったものは、定期処理で `status=inactive` にする。終了日は開始日以降でなければならない。 | `submodules/Wallos/CHANGELOG.md`（cancelation reminders）。自動停止は LifePipe の決定。 |
| SUB-BR-11 | 更新予定の取得（SUB-UC-08）は、期間 `[from, to]`（両端を含む）にある支払日を、有効なサブスクリプションごとにすべて列挙する。列挙は `next_payment_date` から始め、SUB-BR-02 の列に沿って `to` まで進める。週ごとのサブスクリプションは期間内に複数回出る。結果は支払日の昇順、同じ日は名前の昇順で並べる。 | `submodules/Wallos/CHANGELOG.md`（not every payment cycle was shown on the calendar、dashboard upcoming payment count） |
| SUB-BR-12 | 更新予定の期間は `from <= to`、かつ長さ 366 日以内とする。違反は 400。`from` の既定は当日、`to` の既定は `from + 7 日`。手動更新で `overdue=true` のものは、期間の `from` が当日以前なら期間外でも先頭に含める。 | LifePipe の決定 |
| SUB-BR-13 | 金額は 0 以上の 10 進数とし、浮動小数点で計算しない。小数の桁数は通貨の補助単位の桁数（JPY は 0、USD は 2 など、ISO 4217 に従う）を超えてはならない。 | `submodules/Wallos/CHANGELOG.md`（use 2 decimal places for price）。桁数の規則は LifePipe の決定。 |
| SUB-BR-14 | 通貨コードは ISO 4217 の 3 文字の英大文字とする。合計額（SUB-UC-12）を出すときは、通貨ごとに合計を分けて返し、為替換算（後回し）を設定した場合だけ基準通貨の合計も返す。 | `submodules/Wallos/README.md`（Multi-Currency support、Currency Conversion） |
| SUB-BR-15 | データは所有者（OIDC の subject）ごとに分離する。他人のサブスクリプション・カテゴリは取得も更新もできず、存在しない場合と同じく 404 を返す。サブスクリプションに指定するカテゴリなどの参照先も、同じ所有者のものでなければ 400 にする。 | `submodules/Wallos/CHANGELOG.md`（enforce foreign-key ownership on subscription save） |
| SUB-BR-16 | カテゴリ名は所有者の中で重複できない（大文字小文字を区別しない）。使用中のカテゴリを削除すると、そのカテゴリを指していたサブスクリプションは未分類（`category_id` なし）になる。 | `submodules/Wallos/CHANGELOG.md`（keep category rows in step with bulk delete） |
| SUB-BR-17 | 支払い済みにする操作（後回し）は、現在の `next_payment_date` を `due_date` とする Payment を作り、`last_paid_on` を更新し、次回支払日を `D(k) > due_date` を満たす最小の `D(k)` へ進める。取り消しは最後の Payment を削除し、次回支払日をその `due_date` に戻す。同じ `due_date` の Payment は 1 件だけ。 | `submodules/Wallos/CHANGELOG.md`（5.11.0 mark/unmark paid）。具体的な動作は LifePipe の決定。 |
| SUB-BR-18 | 月額換算（後回し）は 1 回の金額を次の係数で換算する。`day`: 金額 × 365 ÷ 12 ÷ 間隔。`week`: 金額 × 52 ÷ 12 ÷ 間隔。`month`: 金額 ÷ 間隔。`year`: 金額 ÷ (12 × 間隔)。年額は月額 × 12。表示時に通貨の桁数で四捨五入する。 | `submodules/Wallos/CHANGELOG.md`（api endpoint to calculate monthly cost、store weekly the total yearly cost）。係数は LifePipe の決定。 |
| SUB-BR-19 | 支払い前の通知（後回し）は、支払日の `notify_days_before` 日前（0 は当日）に 1 回送る。日数は 0〜180。支払日を過ぎた後には送らない。 | `submodules/Wallos/CHANGELOG.md`（notifications up to 180 days before、allow notifications on due date、notifications would also be sent x days after） |
| SUB-BR-20 | 支払い方法（後回し）は、サブスクリプションが使用中なら削除も無効化もできない（409）。 | `submodules/Wallos/CHANGELOG.md`（reject deleting or disabling an in-use payment method） |
| SUB-BR-21 | 為替レート（後回し）の取得は 1 日 1 回までとし、同じ日に取得済みなら取得しない。 | `submodules/Wallos/CHANGELOG.md`（skip an exchange rate refresh that already happened today） |

## LifePipe のワークフローとの関係

- `get_morning_briefing`: 更新予定（SUB-UC-08）を提供する。`life-mcp` は `from=当日`、`to=当日+N 日`（既定 3〜7 日）で取得し、サブスクリプション名・支払日・金額・通貨・手動更新の要否（`renewal_type`、`overdue`）を載せる。合計額は通貨ごとに出す。
- `ingest_purchase`: 関与しない。購入品は subscriptions に振り分けない。
- `prepare_outing`: 関与しない。

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| `GET /subscriptions` | 一覧 | SUB-UC-02 | フィルタ: `status`（既定 `active`）、`category_id`、`renewal_type`。並べ替え: `sort=name\|next_payment_date\|amount`、`order=asc\|desc`。ページング: `limit`（既定 50、最大 200）と `cursor`。 |
| `POST /subscriptions` | 登録 | SUB-UC-01 | `next_payment_date` を省略すると SUB-BR-04 で計算する。201 と作成したリソースを返す。 |
| `GET /subscriptions/{id}` | 取得 | SUB-UC-03 | 他人のものは 404（SUB-BR-15）。 |
| `PATCH /subscriptions/{id}` | 部分更新 | SUB-UC-04、SUB-UC-06 | 停止・再開は `status` の更新で行う（SUB-BR-09）。サイクル変更時の再計算は SUB-BR-06。 |
| `DELETE /subscriptions/{id}` | 削除 | SUB-UC-05 | 204。関連する Payment も削除する。 |
| `POST /subscriptions/next-payment-date:calculate` | 次回支払日の計算 | SUB-UC-07 | 入力: `start_date`、`cycle_unit`、`cycle_interval`、任意で `reference_date`（既定は当日）と `count`（以降の支払日をいくつ返すか、既定 1、最大 12）。保存しない。 |
| `GET /subscriptions/upcoming` | 更新予定の取得 | SUB-UC-08 | クエリ: `from`、`to`（SUB-BR-11、SUB-BR-12）、任意で `category_id`。UpcomingPayment の配列と、通貨ごとの合計額を返す。 |
| （内部ジョブ） | 次回支払日の自動更新 | SUB-UC-09 | 外部 API にはしない。サービス内で毎日実行する（SUB-BR-07、SUB-BR-10）。 |
| `GET /categories` | 一覧 | SUB-UC-10 | `sort_order` の昇順。 |
| `POST /categories` | 登録 | SUB-UC-10 | 名前の重複は 409（SUB-BR-16）。 |
| `PATCH /categories/{id}` | 部分更新 | SUB-UC-10 | 名前・表示順。 |
| `DELETE /categories/{id}` | 削除 | SUB-UC-10 | 使用中なら参照を外して削除する（SUB-BR-16）。 |
| `PUT /categories/order` | 並べ替え | SUB-UC-10 | カテゴリ ID の配列を受け取り、その順に `sort_order` を振り直す。 |
| `POST /subscriptions/{id}/payments` | 支払い済みにする | SUB-UC-11 | 後回し。SUB-BR-17。 |
| `DELETE /subscriptions/{id}/payments/latest` | 支払い済みを取り消す | SUB-UC-11 | 後回し。SUB-BR-17。 |
| `GET /subscriptions/summary` | 月額・年額の合計 | SUB-UC-12、SUB-UC-17 | 後回し。通貨ごとの合計、基準通貨の合計（換算時）、予算との差。SUB-BR-18。 |
| `GET /settings`、`PATCH /settings` | 利用者設定 | SUB-UC-13、SUB-UC-16、SUB-UC-17 | 後回し。タイムゾーン・基準通貨・予算・通知の既定日数。 |
| `GET /payment-methods` ほか CRUD | 支払い方法 | SUB-UC-14 | 後回し。SUB-BR-20。 |
| `GET /household-members` ほか CRUD | 世帯メンバー | SUB-UC-15 | 後回し。 |
| `GET /folders` ほか CRUD | フォルダ | SUB-UC-19 | 後回し。 |
| `GET /subscriptions/upcoming.ics` | iCalendar 配信 | SUB-UC-20 | 後回し。 |
| `GET /subscriptions/export` | エクスポート | SUB-UC-21 | 後回し。`format=csv\|json`。 |
| `POST /subscriptions:batch` | 一括操作 | SUB-UC-22 | 後回し。一括削除・カテゴリ変更。 |

## 対象外

| 機能 | 理由 |
| --- | --- |
| 通知（メール・チャット・プッシュなど）の送信 | MVP では `get_morning_briefing` が更新予定を伝える。通知先ごとの設定や SSRF 対策が大きいため後回しにする。 |
| 為替レートの取得と基準通貨への換算 | 外部 API キーが必要で、MVP の更新予定には不要。通貨ごとの合計で足りる。 |
| 統計・グラフ・予算 | 画面の表示機能で、`life-mcp` のワークフローに不要。 |
| 支払い方法・世帯メンバー・フォルダ・乗り換え先 | 分類の補助で、MVP の CRUD と更新予定には不要。 |
| 支払い済みの記録 | 手動更新の運用に必要だが、MVP は自動更新を中心にする。手動更新は `overdue` で知らせるだけにする。 |
| AI による節約提案、カテゴリ名の翻訳 | 外部 AI への依存が大きく、ドメインの中心ではない。 |
| ロゴの検索・アップロード | ストレージと外部検索が必要で、表示のための機能にすぎない。 |
| iCalendar 配信、CSV/JSON エクスポート、一括操作 | 画面や外部連携の利便機能。必要になったら追加する。 |
| アカウント管理（登録・パスワード・TOTP・管理者画面）、API キー | 共通の ID 基盤（OIDC）に任せる。 |
| データベースのバックアップ・復元、Wallos からのデータ取り込み | 運用基盤の責務。取り込みツールは必要になったら別に作る。 |
| 多言語対応・テーマなどの表示設定 | フロントエンドの責務。 |

## 出典

- `submodules/Wallos/README.md`
- `submodules/Wallos/CHANGELOG.md`
- https://wallosapp.com/
- https://github.com/ellite/Wallos/wiki （Wiki は無く、README と同じ内容が表示された）
- GitHub Issue #17（MVP の範囲）: https://github.com/UtakataKyosui/LifePipe/issues/17
