# tasks: タスク・定期家事管理 の要件

参考元: Vikunja（AGPL-3.0-or-later）。ソースコードは参照していない。

## 責務

tasks サービスは、利用者のやること（単発のタスクと、定期的に繰り返す家事）を管理する。

持つデータ:

- タスク（タイトル、説明、期限、開始日、終了日、優先度、進捗、完了状態、完了日時、繰り返し設定、外出先の場所）
- プロジェクト（タスクをまとめるリスト。階層を持てる）
- ラベル（プロジェクトをまたいでタスクを分類するタグ）
- リマインダー（タスクに付く通知時刻の設定）
- 繰り返しタスクの完了履歴（LifePipe 独自）
- 外出先の場所（LifePipe 独自）

持たないデータ（他ドメインの責務）:

- 予定（カレンダーのイベント）。get_morning_briefing では別ドメインから取得する。
- 食材・消耗品の在庫と買い物リスト。pantry が持つ。prepare_outing では pantry の買い物リストと、tasks の外出先タスクを並べて返す。買い物の品目をタスクとして登録しない。
- 固定費・サブスクリプションの支払い予定。家計・固定費のドメインが持つ。
- 通知の配信（メール・プッシュ）。tasks はリマインダーの時刻を計算して返すまでを持ち、配信は MVP では行わない。

## 参考元の構成

- 主な機能のまとまり: タスク（詳細、説明、ラベル、優先度、進捗、色、担当者、添付ファイル、コメント、チェックリスト、タスク間の関係）、プロジェクト（階層、アーカイブ、複製、お気に入り、Inbox）、ラベル、日付とリマインダー、繰り返しタスク、ビュー（リスト・表・カンバン・ガント）、フィルタと保存済みフィルタ、ダッシュボードと今後の予定一覧、Quick Add Magic（タイトル入力中の記法で項目を設定）、ゴミ箱、共有とチーム、インポート・エクスポート、CalDAV、Webhook、MCP。
- データの保存先: RDB（SQLite が既定。MySQL / MariaDB / PostgreSQL も可）。添付ファイルはローカルディスクまたは S3 互換ストレージ。
- 外部依存: キーバリューストア（メモリまたは Redis。キャッシュ・レート制限に使う）、SMTP（リマインダーと期限切れタスクの通知メール）、Unsplash（プロジェクト背景画像の検索、任意）、定期ジョブ（リマインダーの発火と、毎朝の期限切れタスク通知メール）。
- 認証方式: ローカルアカウント（ユーザー名・パスワード、TOTP）、OpenID Connect、LDAP。API 用には JWT とトークン。プロジェクトの共有リンク（パスワード任意）でアカウントなしのアクセスもできる。
- マルチユーザー / グループの単位: ユーザーごとにプロジェクトを持ち、プロジェクト単位でユーザー・チーム・共有リンクに「読み取り」「読み書き」「管理者」の権限を与える。ラベルは作成者に属する。保存済みフィルタは作成者だけが使う。タイムゾーンはユーザーごとに設定し、リマインダーと期限切れ通知の時刻に影響する。

## エンティティ

### Project（プロジェクト）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | プロジェクトの ID |
| title | string | ○ | 表示名 |
| description | string | | 説明 |
| parent_project_id | 参照(Project) | | 親プロジェクト。未指定なら最上位 |
| identifier | string | | タスク参照用の短い識別子（例: `HOME`）。全プロジェクトで一意 |
| color | string | | 表示色（16進カラーコード） |
| is_inbox | boolean | ○ | Inbox（既定の登録先）なら true。利用者ごとに1つ |
| is_archived | boolean | ○ | アーカイブ済みなら true。アーカイブ中は読み取り専用 |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### Task（タスク）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | タスクの ID |
| project_id | 参照(Project) | ○ | 所属プロジェクト。登録時に省略すると Inbox |
| index | integer | ○ | プロジェクト内の連番。`identifier` と組み合わせて `HOME-12` のような参照を作る |
| title | string | ○ | タイトル |
| description | string | | 説明（Markdown。チェックリスト `- [ ]` を含められる） |
| done | boolean | ○ | 完了済みなら true |
| done_at | date-time | | 完了日時。未完了なら null |
| due_date | date-time | | 期限（この時刻までに終える） |
| start_date | date-time | | 作業予定期間の開始 |
| end_date | date-time | | 作業予定期間の終了 |
| priority | integer | ○ | 優先度。0 = 未設定、1 = 低 〜 5 = 今すぐ。既定 0 |
| percent_done | integer | ○ | 進捗率 0〜100。既定 0 |
| color | string | | 表示色 |
| labels | array<参照(Label)> | | 付いているラベル |
| reminders | array<Reminder> | | リマインダー |
| repeat | RepeatRule | | 繰り返し設定。null なら単発タスク |
| last_completed_at | date-time | | 繰り返しタスクを最後に完了した日時（LifePipe 独自） |
| location | 参照(Location) | | 外出先の場所。外出先タスクを表す（LifePipe 独自） |
| is_overdue | boolean | ○ | 読み取り専用。未完了かつ期限が現在時刻より前なら true |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### RepeatRule（繰り返し設定。Task に埋め込む値オブジェクト）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| mode | enum(default, from_completion, monthly) | ○ | 次回日付の計算方式。default = 元の期限を起点、from_completion = 完了日時を起点、monthly = 毎月同じ日 |
| interval_value | integer | mode が monthly 以外なら ○ | 間隔の数値（1 以上） |
| interval_unit | enum(hour, day, week) | mode が monthly 以外なら ○ | 間隔の単位 |

### Reminder（リマインダー。Task に埋め込む値オブジェクト）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | リマインダーの ID |
| kind | enum(absolute, relative) | ○ | absolute = 日時指定、relative = タスクの日付からの相対指定 |
| remind_at | date-time | kind が absolute なら ○ | 通知日時。relative の場合は読み取り専用で、計算結果を返す（基準日が未設定なら null） |
| relative_to | enum(due_date, start_date, end_date) | kind が relative なら ○ | 相対指定の基準となる日付 |
| relative_offset_seconds | integer | kind が relative なら ○ | 基準日からのずれ（秒）。負の値は基準日より前 |

### Label（ラベル）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | ラベルの ID |
| title | string | ○ | ラベル名。利用者内で一意 |
| description | string | | 説明 |
| color | string | | 表示色 |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### Location（外出先の場所。LifePipe 独自）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 場所の ID |
| name | string | ○ | 場所の名前（例: `ドラッグストア`、`郵便局`、`駅前の図書館`）。利用者内で一意 |
| category | enum(store, public_office, post_office, bank, medical, other) | | 場所の種類 |
| note | string | | 補足（営業時間の目安など） |
| created_at | date-time | ○ | 作成日時 |
| updated_at | date-time | ○ | 更新日時 |

### CompletionRecord（完了履歴。LifePipe 独自）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | ○ | 履歴の ID |
| task_id | 参照(Task) | ○ | 完了したタスク |
| completed_at | date-time | ○ | 完了日時 |
| due_date_at_completion | date-time | | 完了した時点の期限 |
| next_due_date | date-time | | 完了によって計算された次回の期限 |
| created_at | date-time | ○ | 記録日時 |

### UserSettings（利用者設定）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| timezone | string | ○ | IANA タイムゾーン名（例: `Asia/Tokyo`）。当日・期限切れ・リマインダーの判定に使う |
| default_project_id | 参照(Project) | ○ | プロジェクト省略時の登録先。既定は Inbox |
| default_due_time | string | | 日付だけ指定されたときに補う時刻（`HH:MM`） |
| updated_at | date-time | ○ | 更新日時 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| TSK-UC-01 | タスクを登録する（タイトル、説明、期限、開始日・終了日、優先度、ラベル、プロジェクト、リマインダー、繰り返し、場所） | MVP | https://vikunja.io/help/tasks/ 、Issue #28 |
| TSK-UC-02 | タスクを取得・更新・削除する | MVP | https://vikunja.io/help/tasks/ |
| TSK-UC-03 | タスクを完了にする（完了日時を指定できる） | MVP | https://vikunja.io/help/tasks/ 、Issue #28 |
| TSK-UC-04 | 完了したタスクを未完了に戻す | MVP | https://vikunja.io/help/tasks/ |
| TSK-UC-05 | タスクを一覧する（プロジェクト、ラベル、完了状態、期限の範囲、優先度、場所で絞り込み、期限・優先度などで並べ替え） | MVP | https://vikunja.io/help/filters/ 、https://vikunja.io/help/views/ |
| TSK-UC-06 | 繰り返しタスク（定期家事）を登録し、完了するたびに次回の期限を自動で計算する | MVP | https://vikunja.io/help/dates-and-reminders/ 、Issue #28 |
| TSK-UC-07 | 当日が期限のタスクと期限切れのタスクを取得する（get_morning_briefing 用） | MVP | https://vikunja.io/help/dashboard/ 、Issue #28 |
| TSK-UC-08 | 外出先タスク（場所が設定された未完了タスク）を場所ごとに取得する（prepare_outing 用） | MVP | LifePipe 独自（Issue #28） |
| TSK-UC-09 | プロジェクトを登録・取得・更新・削除・一覧する | MVP | https://vikunja.io/help/projects/ |
| TSK-UC-10 | ラベルを登録・取得・更新・削除・一覧する | MVP | https://vikunja.io/help/labels/ |
| TSK-UC-11 | 外出先の場所を登録・取得・更新・削除・一覧する | MVP | LifePipe 独自（Issue #28） |
| TSK-UC-12 | 繰り返しタスクの完了履歴を取得する | MVP | LifePipe 独自 |
| TSK-UC-13 | 利用者設定（タイムゾーン、既定のプロジェクト、既定の期限時刻）を取得・更新する | MVP | https://vikunja.io/help/dates-and-reminders/ 、https://vikunja.io/docs/config-options/ |
| TSK-UC-14 | プロジェクトをアーカイブ・解除する | 後回し | https://vikunja.io/help/projects/ |
| TSK-UC-15 | 今後の期間（例: 今日から7日後まで）に期限があるタスクを取得する | 後回し | https://vikunja.io/help/dashboard/ |
| TSK-UC-16 | リマインダーの時刻に通知を配信する | 後回し | https://vikunja.io/help/dates-and-reminders/ |
| TSK-UC-17 | タスクを複製する | 後回し | https://vikunja.io/help/tasks/ |
| TSK-UC-18 | タスク間の関係（親子、ブロック、関連など）を設定する | 後回し | https://vikunja.io/help/task-relations/ |
| TSK-UC-19 | 削除したタスク・プロジェクトをゴミ箱から復元する | 後回し | https://vikunja.io/help/tasks/ 、https://vikunja.io/help/projects/ |
| TSK-UC-20 | 保存済みフィルタを作成し、プロジェクトをまたいだ一覧を作る | 後回し | https://vikunja.io/help/saved-filters/ |
| TSK-UC-21 | 1行の自然文（記法付き）からタスクを登録する（Quick Add Magic 相当） | 後回し | https://vikunja.io/help/quick-add-magic/ |

## 業務ルール

| ID | ルール | 出典 |
| --- | --- | --- |
| TSK-BR-01 | タスクは必ず1つのプロジェクトに属する。登録時にプロジェクトを省略した場合は、利用者設定の既定プロジェクト（初期値は Inbox）に登録する。Inbox は利用者ごとに1つ作られ、削除できない。 | https://vikunja.io/help/projects/ 、https://vikunja.io/help/dashboard/ |
| TSK-BR-02 | 優先度は 0〜5 の整数。0 は未設定、1 が最も低く 5 が最も高い（今すぐ）。範囲外の値は 400 で拒否する。 | https://vikunja.io/help/tasks/ 、https://vikunja.io/help/quick-add-magic/ |
| TSK-BR-03 | 進捗率は 0〜100 の整数。範囲外の値は拒否する。 | https://vikunja.io/help/tasks/ |
| TSK-BR-04 | 期限（due_date）は「この時刻までに終える」日時。期限が現在時刻より前で、かつ未完了のタスクを期限切れ（is_overdue = true）とする。完了済みのタスクは期限が過ぎていても期限切れにしない。期限が未設定のタスクは期限切れにならない。 | https://vikunja.io/help/dates-and-reminders/ |
| TSK-BR-05 | 開始日（start_date）と終了日（end_date）は作業を予定する期間を表し、期限とは独立している（例: 期限 11/30 の書類を 11/20〜11/28 に作業する）。開始日と終了日の両方があるときは 開始日 ≦ 終了日 でなければならず、違反は 400 で拒否する。期限が終了日より前でもよい（警告はしない）。 | https://vikunja.io/help/dates-and-reminders/ 、開始日 ≦ 終了日の検証は LifePipe 独自 |
| TSK-BR-06 | リマインダーは1タスクに複数付けられる。absolute は remind_at の日時に発火する。relative は relative_to で指定した日付（期限・開始日・終了日）に relative_offset_seconds を加えた日時に発火する（例: 期限 11/20 18:00、offset -3600 なら 11/20 17:00）。基準の日付が未設定の relative リマインダーは発火せず、remind_at は null を返す。基準日が変わると remind_at も再計算する。 | https://vikunja.io/help/dates-and-reminders/ |
| TSK-BR-07 | 完了済みのタスクのリマインダーは発火させない。 | submodules/vikunja/CHANGELOG.md（reminders: Exclude notifications for completed tasks） |
| TSK-BR-08 | 日付・時刻の判定（当日、期限切れ、リマインダー）は利用者設定のタイムゾーンで行う。API の日時は RFC 3339 形式（タイムゾーンオフセット付き）で受け渡しする。 | https://vikunja.io/docs/config-options/（defaultsettings.timezone） |
| TSK-BR-09 | 期限に日付だけ（`YYYY-MM-DD`）が指定された場合、利用者設定の既定の期限時刻（default_due_time）を補う。既定の期限時刻が未設定なら 23:59 を補う。明示された時刻は変更しない。 | https://vikunja.io/help/dates-and-reminders/ 、未設定時の 23:59 は LifePipe 独自 |
| TSK-BR-10 | 単発タスク（repeat が null）の状態遷移: 未完了 →（完了操作）→ 完了。このとき done = true、done_at = 完了日時（指定がなければ現在時刻）とする。完了 →（未完了に戻す操作）→ 未完了。このとき done = false、done_at = null とする。完了済みのタスクへの完了操作、未完了のタスクへの未完了に戻す操作は、状態を変えずに現在の状態を返す（冪等）。 | https://vikunja.io/help/tasks/ 、done_at を null に戻すことと冪等性は LifePipe 独自 |
| TSK-BR-11 | 繰り返しタスクの完了操作: タスクは完了状態にならず、未完了のまま残る（新しいタスクは作らない）。完了操作のたびに、TSK-BR-12〜14 の方式で期限・開始日・終了日・absolute リマインダーを次回へ進め、last_completed_at を完了日時で更新し、CompletionRecord を1件作る。説明中のチェックリストの項目（`- [x]`）はすべて未チェック（`- [ ]`）に戻す。done は false、done_at は null のままとする。繰り返し設定を外したタスクは単発タスクとして TSK-BR-10 に従う。 | https://vikunja.io/help/dates-and-reminders/ 、完了履歴は LifePipe 独自 |
| TSK-BR-12 | 繰り返し方式 default（元の期限を起点）: 現在の期限に間隔を加算する。加算した結果が完了日時以前なら、完了日時より後になるまで間隔の加算を繰り返す（例: 間隔3日、期限 11/10、11/18 に完了 → 11/13、11/16 はどちらも過去なので次回は 11/19）。期限が予定どおりの曜日・時刻に揃い続けるので、「毎週月曜のゴミ出し」のように曜日が決まった家事に使う。 | https://vikunja.io/help/dates-and-reminders/ 、過去分を飛ばす挙動は submodules/vikunja/CHANGELOG.md（repeating-task handler / ancient repeating due dates）からの推定 |
| TSK-BR-13 | 繰り返し方式 from_completion（完了日時を起点）: 次回の期限 = 完了日時 + 間隔。時刻部分は元の期限の時刻を保つ（例: 間隔3日、期限 11/10 20:00、11/12 08:00 に完了 → 次回の期限は 11/15 20:00）。default との比較: 同じ条件（間隔3日、期限 11/10、完了 11/12）で default なら 11/13、from_completion なら 11/15。「植物の水やりを3日おき」のように前回の実施日から数える家事に使う。期限が未設定の繰り返しタスクは、完了日時 + 間隔を次回の期限にする。 | https://vikunja.io/help/dates-and-reminders/ 、時刻を保つことは LifePipe 独自 |
| TSK-BR-14 | 繰り返し方式 monthly: 間隔の値を使わず、期限を翌月の同じ日に進める。翌月にその日がない場合は月末日にする（例: 1/31 → 2/28、閏年は 2/29）。月末日に寄せた後も元の日を基準にする（2/28 の次は 3/31）。 | https://vikunja.io/help/dates-and-reminders/ 、submodules/vikunja/CHANGELOG.md（Clamp day when advancing a monthly repeating task） 、元の日を保持することは LifePipe 独自 |
| TSK-BR-15 | 繰り返しで日付を進めるとき、開始日・終了日・absolute リマインダーは期限と同じ差分だけ進める（期限が3日進めば、開始日・終了日・リマインダーもそれぞれ3日進む）。期限が未設定のときは、最も早い日付（開始日、なければ終了日）を基準に差分を計算する。relative リマインダーは基準日から再計算されるため個別には進めない。進めた結果のリマインダーが完了日時より前になる場合は、完了日時より後になるまで間隔を加算する。 | https://vikunja.io/help/dates-and-reminders/ 、submodules/vikunja/CHANGELOG.md（Don't wrap reminders into the past when repeating from current date） 、同じ差分で進める規則は LifePipe 独自 |
| TSK-BR-16 | 繰り返し間隔は 1 時間以上 10 年以下とする。範囲外は 400 で拒否する。mode が default または from_completion のときは interval_value と interval_unit が必須。 | submodules/vikunja/CHANGELOG.md（Cap repeat_after at 10 years） 、下限は LifePipe 独自 |
| TSK-BR-17 | 完了操作の完了日時は省略可能で、省略時は現在時刻。過去の日時を指定できる（例: 昨日実施した家事を今日記録する）。未来の日時は拒否する。from_completion の次回計算には指定された完了日時を使う。 | LifePipe 独自（Issue #28） |
| TSK-BR-18 | 当日が期限のタスク: 利用者のタイムゾーンで当日 0:00 以上、翌日 0:00 未満に期限がある未完了タスク。繰り返しタスク（定期家事）も含める。期限切れのタスク（期限が当日 0:00 より前で未完了）は、当日分とは別のグループで返す。 | https://vikunja.io/help/dashboard/ 、https://vikunja.io/help/filters/ 、グループ分けは LifePipe 独自 |
| TSK-BR-19 | 外出先タスクは location が設定された未完了のタスクとする。prepare_outing 用の取得では場所ごとにまとめ、場所の中では期限の早い順（期限なしは最後）、同じ期限なら優先度の高い順に並べる。場所の指定があればその場所のタスクだけを返す。 | LifePipe 独自（Issue #28） |
| TSK-BR-20 | ラベル・場所・優先度などで絞り込むとき、その項目の値を持たないタスクは結果に含めない（例: ラベル「買い出し」で絞り込むと、ラベルのないタスクは返さない）。 | LifePipe 独自（参考元はフィルタ設定で値なしのタスクを含めるのが既定: https://vikunja.io/help/filters/） |
| TSK-BR-21 | 一覧の既定は未完了のタスクだけを返す。完了済みを含めるには done の絞り込みを明示する。並べ替えは期限・開始日・終了日・優先度・進捗・作成日時・更新日時・タイトルの1項目と昇順・降順を指定できる。期限の昇順で並べるとき、期限なしは最後にする。 | https://vikunja.io/help/views/ 、https://vikunja.io/help/saved-filters/ |
| TSK-BR-22 | 一覧はページ分割する。1ページの件数の既定は 50、上限は 200。 | https://vikunja.io/docs/config-options/（service.maxitemsperpage） 、件数は LifePipe 独自 |
| TSK-BR-23 | ラベルはプロジェクトに属さず、同じラベルを複数のプロジェクトのタスクに付けられる。ラベル名は利用者内で一意。タスクにラベル名で指定されたラベルが存在しない場合は新規に作成して付ける。ラベルを削除すると、付いているタスクからも外れる（タスクは残る）。 | https://vikunja.io/help/labels/ 、削除時の扱いは LifePipe 独自 |
| TSK-BR-24 | プロジェクトは親プロジェクトを持てる。自分自身や自分の子孫を親にすることはできない。プロジェクトを削除すると、その子プロジェクトと所属するタスクも削除する（MVP では即時削除。ゴミ箱は後回し）。 | https://vikunja.io/help/projects/ 、循環の禁止は LifePipe 独自 |
| TSK-BR-25 | アーカイブ中のプロジェクトとそのタスクは読み取り専用で、タスクの登録・更新・完了操作は 409 で拒否する。 | https://vikunja.io/help/projects/ |
| TSK-BR-26 | プロジェクトの identifier は全プロジェクトで一意。タスクの index はプロジェクト内で 1 から振る連番で、別プロジェクトへ移動すると移動先で新しい番号を振る。 | https://vikunja.io/help/projects/ 、移動時の採番は LifePipe 独自 |
| TSK-BR-27 | 場所を削除すると、その場所が設定されたタスクの location は null になる（タスクは残る）。場所名は利用者内で一意。 | LifePipe 独自 |

## LifePipe のワークフローとの関係

- get_morning_briefing: 当日が期限の未完了タスク（定期家事を含む）と、期限切れの未完了タスクを別グループで提供する（TSK-UC-07、TSK-BR-18）。各タスクはタイトル、期限、優先度、ラベル、プロジェクト名、繰り返しかどうかを含む。
- ingest_purchase: 関与しない。購入した品目の振り分け先に tasks は含まれない。
- prepare_outing: 外出先タスク（場所が設定された未完了タスク）を場所ごとにまとめて提供する（TSK-UC-08、TSK-BR-19）。pantry の買い物リストはゲートウェイ側で並べて返す。参考元には場所の概念がないため、場所（Location）は LifePipe 独自のエンティティとして持つ。代替案として、場所を表すラベル（例: `@ドラッグストア` のような接頭辞付きラベル）で表す方法もあるが、ラベルと場所の用途が混ざるため Location を主案とする。

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| projects | 一覧（フィルタ: archived、parent_project_id） | TSK-UC-09 | ページ分割 |
| projects | 登録 / 取得 / 更新 / 削除 | TSK-UC-09 | Inbox は削除不可（TSK-BR-01）。削除は子プロジェクトとタスクを含む（TSK-BR-24） |
| projects/{id}/archive | 登録（アーカイブ） / 削除（解除） | TSK-UC-14 | 後回し |
| tasks | 一覧（フィルタ: project_id、label_ids、location_id、done、due_from、due_to、priority_min、overdue、repeating。並べ替え: sort_by、order） | TSK-UC-05 | 既定は未完了のみ（TSK-BR-21）。値なしは除外（TSK-BR-20）。ページ分割（TSK-BR-22） |
| tasks | 登録 / 取得 / 更新 / 削除 | TSK-UC-01、TSK-UC-02、TSK-UC-06 | 更新は部分更新（PATCH）。labels はラベル ID またはラベル名で指定できる（TSK-BR-23） |
| tasks/{id}/complete | 実行（POST、本文: completed_at 任意） | TSK-UC-03、TSK-UC-06 | 単発は完了に、繰り返しは次回へ進める（TSK-BR-10〜17）。更新後のタスクを返す |
| tasks/{id}/uncomplete | 実行（POST） | TSK-UC-04 | 単発タスクのみ意味を持つ（TSK-BR-10） |
| tasks/{id}/completions | 一覧 | TSK-UC-12 | 完了日時の降順 |
| tasks/today | 取得（パラメータ: date 任意、既定は利用者のタイムゾーンでの今日） | TSK-UC-07 | 返り値は due_today と overdue の2グループ（TSK-BR-18）。get_morning_briefing 用 |
| tasks/outing | 取得（パラメータ: location_id 任意） | TSK-UC-08 | 場所ごとのグループで返す（TSK-BR-19）。prepare_outing 用 |
| tasks/upcoming | 取得（パラメータ: from、to、include_overdue、include_no_due） | TSK-UC-15 | 後回し |
| labels | 一覧 / 登録 / 取得 / 更新 / 削除 | TSK-UC-10 | |
| locations | 一覧 / 登録 / 取得 / 更新 / 削除 | TSK-UC-11 | LifePipe 独自 |
| settings | 取得 / 更新 | TSK-UC-13 | 利用者ごとに1件 |

## 対象外

- 通知の配信（メール、プッシュ、毎朝の期限切れ通知メール）: MVP ではリマインダーの時刻を保持・計算するだけとし、配信はゲートウェイや別の通知手段の検討後に扱う（後回し）。
- Quick Add Magic 相当の自然文解析: ゲートウェイ側の LLM が自然文を構造化して API を呼ぶため、tasks サービスでは持たない（後回し）。
- タスク間の関係（親子、ブロックなど）、タスクの複製: 定期家事と当日タスクの取得に不要なため後回し。
- コメント、添付ファイル、カバー画像、タスクの色以外の装飾: 個人利用の MVP に不要。
- 担当者、共有（ユーザー、チーム、共有リンク）、権限: 単一利用者の自己ホストを前提とするため対象外。
- ビュー（リスト・表・カンバン・ガント）、カンバンのバケット・WIP 制限: 画面表示の設定であり、API ゲートウェイの責務ではない。
- 保存済みフィルタ、独自のフィルタ構文: 一覧 API の絞り込みパラメータで代替する（後回し）。
- ゴミ箱（30日間の保持と復元）: MVP では即時削除とする（後回し）。
- お気に入り、プロジェクトの背景画像、プロジェクトの複製: 表示上の機能のため対象外。
- 「第1火曜日」「2週ごとの火曜日」など柔軟な繰り返し規則: 参考元でも未対応で、MVP の定期家事は3方式で表せる。
- CalDAV、Webhook、外部サービスからのインポート・エクスポート: 連携は LifePipe のゲートウェイが担う。

## 出典

- submodules/vikunja/README.md
- submodules/vikunja/CHANGELOG.md
- https://vikunja.io/docs/
- https://vikunja.io/docs/config-options/
- https://vikunja.io/help/
- https://vikunja.io/help/tasks/
- https://vikunja.io/help/projects/
- https://vikunja.io/help/dates-and-reminders/
- https://vikunja.io/help/quick-add-magic/
- https://vikunja.io/help/labels/
- https://vikunja.io/help/filters/
- https://vikunja.io/help/saved-filters/
- https://vikunja.io/help/views/
- https://vikunja.io/help/task-relations/
- https://vikunja.io/help/sharing-and-teams/
- https://vikunja.io/help/dashboard/
- GitHub Issue #28（LifePipe の tasks ドメインの MVP 範囲）
