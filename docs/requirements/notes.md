# notes: 思考・ログ・メモ の要件

参考元: Memos（MIT）。ソースコードは参照していない。

## 責務

notes サービスは、短い思考の記録・日々のログ・購買メモを時系列で保存し、検索・絞り込み・取り出しを提供する。

持つデータ:

- メモ（Markdown 本文、公開範囲、ピン留め、アーカイブ状態、作成日時・更新日時）
- 本文から導出するタグと内容プロパティ（リンク・コード・チェックリストの有無など）
- メモに添付するファイル（レシート画像、PDF など）とそのメタデータ
- 購買メモ・領収書ログ（`ingest_purchase` が記録する、タグ付きのメモと添付ファイル）

持たないデータ:

- 品目単位の在庫・数量・賞味期限（pantry）、長期保有品（inventory）、衣類（wardrobe）。購買メモは「何をいつ買ったか」の記録であり、在庫の正本ではない。
- 固定費・サブスクリプションの契約情報（subscriptions）、タスク・期限（tasks）、予定（Google Calendar）。
- ユーザーアカウント・認証情報。認証は LifePipe ゲートウェイ側で行い、ゲートウェイが渡す呼び出し元の利用者 ID を notes はメモと添付ファイルの所有者（owner_id）として保存する。利用者は世帯の数人を想定し、利用者の登録・管理は notes の外で行う。
- LLM による品目分類の結果。分類は `ingest_purchase` ワークフロー側で行い、notes は分類後の記録だけを受け取る。

## 参考元の構成

- 主な機能のまとまり: メモの作成・編集（Markdown、リッチエディタ）、タイムライン・カレンダー・地図での閲覧、タグ、全文検索と CEL 式によるフィルタ、保存済みフィルタ（View）、添付ファイルとファイルライブラリ、メモ間リンク（Relation）、コメント・リアクション・メンション・受信箱、共有リンク、Space（複数ユーザーの共同領域）、エクスポート・インポート（ZIP）、Webhook、MCP サーバー、音声の文字起こし。
- データの保存先: SQLite（既定）、MySQL、PostgreSQL のいずれか。添付ファイルの実体はデータベース、ローカルファイルシステム、S3 互換ストレージのいずれかに保存する。保存先は名前付きで複数登録でき、既定の保存先を変えても既存ファイルは移動しない。
- 外部依存: データベース、任意のオブジェクトストレージ、任意の AI プロバイダ（音声の文字起こし用、利用者が鍵を用意する）、Webhook の送信先。ジョブキューは持たない。
- 認証方式: パスワードログインと SSO。API は短命のアクセストークン、長命のリフレッシュトークン、個人アクセストークン（Bearer で送る。値は作成時に一度だけ表示され、ハッシュで保存される）。MCP サーバーも同じ個人アクセストークンで認証し、REST API と同じ権限で動く。
- マルチユーザーの単位: 1 インスタンスに複数ユーザー。メモは常に作成者が所有する。Space はメンバーと役割（ADMIN / USER）を持つ共同領域で、メモは未割り当てか 1 つの Space に属する。インスタンス管理者は個々のメモを作成者に関係なく読み書きできる。
- 利用上限: ユーザーごとにメモ件数、メモ 1 件の本文サイズ、保存容量の合計、ファイル 1 件のサイズの上限を持つ。既定は本文 8 KiB、ファイル 32 MiB で、件数と合計容量は無制限。

## エンティティ

### Note（メモ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | メモの ID。サーバーが採番する。英数字とハイフン、1〜36 文字、先頭と末尾は英数字。 |
| owner_id | string | 必須 | 所有者の利用者 ID。ゲートウェイが渡す呼び出し元の ID をサーバーが設定し、変更できない。 |
| content | string | 必須 | Markdown 本文。空文字は不可。UTF-8 のバイト長は本文上限以下（既定 8 KiB）。 |
| visibility | enum(PRIVATE, PROTECTED, PUBLIC) | 必須 | 公開範囲。省略時は PRIVATE。 |
| state | enum(NORMAL, ARCHIVED) | 必須 | 状態。作成時は NORMAL。 |
| pinned | boolean | 必須 | ピン留め。既定は false。 |
| tags | array<string> | 必須 | 本文から導出したタグ（祖先タグを含む）。読み取り専用。空配列もありうる。 |
| property | 参照(NoteProperty) | 必須 | 本文から導出した内容プロパティ。読み取り専用。 |
| attachments | array<参照(Attachment)> | 必須 | 紐づく添付ファイル。表示順を保つ。空配列もありうる。 |
| source | enum(MANUAL, INGEST_PURCHASE, API) | 必須 | 作成経路。既定は API。`ingest_purchase` が作ったメモは INGEST_PURCHASE。 |
| external_ref | string | 任意 | 呼び出し元が付ける冪等キー（例: レシートの取り込み ID）。同じ所有者の中で一意。 |
| created_at | date-time | 必須 | 作成日時（UTC）。作成時に呼び出し元が指定できる。省略時はサーバー時刻。 |
| updated_at | date-time | 必須 | 更新日時（UTC）。作成時に指定できる。以後は本文・公開範囲・状態・ピン留め・添付の変更で更新する。 |

### NoteProperty（内容プロパティ、Note に埋め込み）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| has_link | boolean | 必須 | 本文に Markdown のリンクがある。 |
| has_code | boolean | 必須 | 本文にコードブロックまたはインラインコードがある。 |
| has_task_list | boolean | 必須 | 本文にチェックリスト項目がある。 |
| has_incomplete_tasks | boolean | 必須 | 本文に未チェックのチェックリスト項目（`- [ ]`）がある。 |
| has_inline_image | boolean | 必須 | 本文に Markdown の画像記法がある（コード内は除く）。 |
| has_attachments | boolean | 必須 | 紐づく添付ファイルが 1 件以上ある。 |
| has_image | boolean | 必須 | has_inline_image が真、または MIME タイプが `image/` で始まる添付ファイルが 1 件以上ある。 |

### Attachment（添付ファイル）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| id | string | 必須 | 添付ファイルの ID。Note.id と同じ文字規則。 |
| owner_id | string | 必須 | アップロードした利用者の ID。サーバーが設定し、変更できない。 |
| note_id | 参照(Note) | 任意 | 紐づくメモ。未設定なら未使用（どのメモにも紐づいていない）。 |
| filename | string | 必須 | 元のファイル名。 |
| mime_type | string | 必須 | IANA メディアタイプ（例: `image/jpeg`、`application/pdf`）。サーバーが内容から判定し直す。 |
| size | integer | 必須 | バイト数。外部リンクの場合は呼び出し元の申告値または 0。 |
| sha256 | string | 任意 | 内容の SHA-256（小文字 16 進 64 文字）。実体を保存したときは必須。 |
| storage | enum(STORED, EXTERNAL) | 必須 | 実体を保存しているか、外部リンクだけを持つか。 |
| external_link | string | 任意 | storage が EXTERNAL のときの URL。STORED のときは持たない。 |
| media_metadata | 参照(MediaMetadata) | 任意 | 画像の幅・高さなど。 |
| created_at | date-time | 必須 | アップロード日時。 |
| updated_at | date-time | 必須 | 更新日時（ファイル名の変更、メモへの紐づけ・解除）。 |

### MediaMetadata（添付ファイルのメディア情報、Attachment に埋め込み）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| width | integer | 任意 | 画像・動画の幅（px）。 |
| height | integer | 任意 | 画像・動画の高さ（px）。 |
| duration_seconds | number | 任意 | 音声・動画の長さ（秒）。 |

### Tag（タグ集計、導出データ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| name | string | 必須 | タグ名（`#` を含まない。例: `purchase/grocery`）。 |
| note_count | integer | 必須 | このタグを持つ NORMAL 状態のメモの件数。 |
| last_used_at | date-time | 必須 | このタグを持つメモの最新の created_at。 |

Tag は Note.tags から集計する読み取り専用のデータで、個別に作成・更新・削除しない。作成日時の代わりに last_used_at を持つ。

### Usage（利用状況、導出データ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| note_count | integer | 必須 | メモの件数（アーカイブ済みを含む）。 |
| storage_bytes | integer | 必須 | 実体を保存した添付ファイルの合計バイト数（未使用を含み、外部リンクを除く）。 |
| limits | 参照(UsageLimits) | 必須 | 適用中の上限。 |

### UsageLimits（利用上限、設定）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| note_count | integer | 必須 | メモ件数の上限。0 は無制限。既定 0。 |
| content_bytes | integer | 必須 | メモ 1 件の本文の上限（バイト）。0 は無制限。既定 8192。 |
| storage_bytes | integer | 必須 | 添付ファイル合計の上限（バイト）。0 は無制限。既定 0。 |
| upload_bytes | integer | 必須 | ファイル 1 件の上限（バイト）。0 は無制限。既定 33554432。 |
| updated_at | date-time | 必須 | 設定の更新日時。 |

## ユースケース

| ID | ユースケース | 優先度 | 出典 |
| --- | --- | --- | --- |
| NOT-UC-01 | Markdown 本文でメモを作成する。公開範囲と作成日時を指定できる。 | MVP | https://usememos.com/docs/usage/memos 、submodules/memos/docs/design/memos-export-format.md |
| NOT-UC-02 | メモを 1 件取得する。 | MVP | https://usememos.com/docs/usage/memos |
| NOT-UC-03 | メモの本文・公開範囲・作成日時・更新日時を編集する。タグと内容プロパティは本文から再計算される。 | MVP | https://usememos.com/docs/usage/memos 、https://usememos.com/docs/usage/tags |
| NOT-UC-04 | メモを削除する。紐づく添付ファイルも削除される。 | MVP | https://usememos.com/docs/usage/attachments |
| NOT-UC-05 | メモをピン留め・解除する。 | MVP | https://usememos.com/docs/usage/memos |
| NOT-UC-06 | メモをアーカイブし、アーカイブから戻す。アーカイブ済みのメモを一覧する。 | MVP | https://usememos.com/docs/usage/search-archive |
| NOT-UC-07 | 本文の全文検索でメモを探す。 | MVP | https://usememos.com/docs/usage/search-archive |
| NOT-UC-08 | タグ（階層を含む）、期間、公開範囲、ピン留め、状態、内容プロパティ（添付・画像・リンク・未完了タスクの有無）でメモを絞り込み、新しい順または古い順に一覧する。 | MVP | https://usememos.com/docs/usage/views 、submodules/memos/docs/design/memo-attachment-filters.md |
| NOT-UC-09 | 使われているタグを件数付きで一覧する。 | MVP | https://usememos.com/docs/usage/tags |
| NOT-UC-10 | ファイルをアップロードし、メモに紐づける・紐づけを外す。メモの添付ファイルを一覧する。 | MVP | https://usememos.com/docs/usage/attachments |
| NOT-UC-11 | 未使用の添付ファイルを一覧し、個別または一括で削除する。 | MVP | https://usememos.com/docs/usage/attachments |
| NOT-UC-12 | 購買メモ・領収書ログを記録する（`ingest_purchase`）。レシート画像を添付し、購買日を作成日時にして、購買タグ付きのメモを 1 回の操作で作る。同じ取り込みの再送では重複を作らない。 | MVP | README.md §4.2、GitHub Issue #29、submodules/memos/docs/design/memos-export-format.md |
| NOT-UC-13 | LLM に文脈として渡すため、期間とタグを指定してメモを古い順にまとめて取得する。件数またはバイト数の上限で切り詰め、切り詰めたことを返す。 | MVP | GitHub Issue #29、https://usememos.com/docs/integrations/mcp |
| NOT-UC-14 | 利用状況と利用上限を確認する。上限を設定する。 | 後回し | submodules/memos/docs/design/user-usage-limits.md |
| NOT-UC-15 | メモにコメントする。コメントを一覧する。 | 後回し | https://usememos.com/docs/usage/reactions-comments |
| NOT-UC-16 | メモに絵文字でリアクションする・取り消す。 | 後回し | https://usememos.com/docs/usage/reactions-comments |
| NOT-UC-17 | メモ同士を参照関係（Relation）でつなぐ。 | 後回し | https://usememos.com/docs/usage/memos |
| NOT-UC-18 | 1 件のメモの共有リンクを期限付きで発行・失効する。 | 後回し | https://usememos.com/docs/usage/sharing |
| NOT-UC-19 | よく使う絞り込み条件に名前を付けて保存する（View）。 | 後回し | https://usememos.com/docs/usage/views |
| NOT-UC-20 | メモの作成・更新・削除を Webhook で外部に通知する。 | 後回し | https://usememos.com/docs/integrations/webhooks |
| NOT-UC-21 | メモに位置情報を付け、位置情報のあるメモを絞り込む。 | 後回し | https://usememos.com/docs/usage/memos |
| NOT-UC-22 | メモと添付ファイルを ZIP でエクスポート・インポートする。 | 後回し | submodules/memos/docs/design/memos-export-format.md |
| NOT-UC-23 | 音声の添付ファイルを文字起こしして本文に入れる。 | 後回し | https://usememos.com/docs/usage/attachments |

## 業務ルール

| ID | ルール | 出典 |
| --- | --- | --- |
| NOT-BR-01 | タグの抽出: 本文の通常テキスト（見出し・リスト項目を含む）中の `#` に続く文字列をタグとする。使える文字は各言語の文字、結合文字、数字、`_`、絵文字、`-`、`+`、`&`。数字だけのタグ（`#2026`）も有効。語中のアポストロフィは含めてよい。空白とそれ以外の記号でタグは終わる（`#release.notes` は `release`、`#C++` と `#R&D` はそのまま）。 | https://usememos.com/docs/usage/tags |
| NOT-BR-02 | タグの階層: `/` は空でない区切りの間にだけ置ける。先頭・末尾の `/` と連続する `/` は不可。`#purchase/grocery` は `purchase/grocery` と祖先の `purchase` の両方をメモのタグとする。 | https://usememos.com/docs/usage/tags |
| NOT-BR-03 | タグを抽出しない箇所: インラインコード、コードブロック、リンク、画像、URL の中の `#`。`\#` と書いた `#` は文字として扱う。 | https://usememos.com/docs/usage/tags |
| NOT-BR-04 | タグは大文字と小文字を区別する（`#Work` と `#work` は別のタグ）。タグの重複は 1 つにまとめる。 | https://usememos.com/docs/usage/tags |
| NOT-BR-05 | tags と、property のうち has_link・has_code・has_task_list・has_incomplete_tasks・has_inline_image は本文から導出する読み取り専用の値で、作成・本文更新・インポートのたびにサーバーが再計算する（has_attachments と has_image は添付の紐づけにも依存する。NOT-BR-20）。API でタグを直接指定・変更することはできない。タグを付けたいときは本文に `#tag` を書く。 | https://usememos.com/docs/usage/tags 、submodules/memos/docs/design/memos-export-format.md |
| NOT-BR-06 | タグによる絞り込み: タグ `X` を指定すると、`X` そのものと `X/` で始まる子孫タグを持つメモが該当する。複数指定は「いずれかを持つ」（OR）。タグなしのメモだけを探す指定もできる。 | https://usememos.com/docs/usage/views |
| NOT-BR-07 | 公開範囲（visibility）: PRIVATE は所有者だけが読める。PROTECTED は LifePipe に認証済みの利用者が読める。PUBLIC は認証なしでも読めるが、インスタンス設定で公開アクセスを有効にしているときだけで、無効なら PROTECTED と同じに扱う。作成時の既定は PRIVATE。公開範囲に関係なく、メモと添付ファイルの更新・アーカイブ・ピン留め・削除は所有者だけができる。 | https://usememos.com/docs/usage/sharing 、https://usememos.com/docs/usage/reactions-comments |
| NOT-BR-08 | 一覧・検索・タグ集計・文脈取得は、呼び出し元が読めるメモだけを返す。読めないメモの存在は件数にも含めない。 | https://usememos.com/docs/usage/search-archive |
| NOT-BR-09 | 購買メモ（source が INGEST_PURCHASE）は常に PRIVATE で作成する。購買履歴は個人の生活データのため、公開範囲の指定は受け付けない。 | README.md §2（プライバシー・バイ・デザイン）、README.md §4.2 |
| NOT-BR-10 | 状態の遷移: state は NORMAL と ARCHIVED の 2 値。NORMAL → ARCHIVED（アーカイブ）と ARCHIVED → NORMAL（復元）だけがある。アーカイブしても本文・タグ・添付・公開範囲は保持する。 | https://usememos.com/docs/usage/search-archive |
| NOT-BR-11 | アーカイブ済みのメモは、state を指定しない一覧・検索・タグ集計・文脈取得から除外する。state=ARCHIVED を指定したときだけ返す。ID を指定した取得では状態に関係なく返す。 | https://usememos.com/docs/usage/search-archive 、https://usememos.com/docs/usage/memos |
| NOT-BR-12 | ピン留め（pinned）は state と独立した真偽値。一覧で並べ替えを「ピン留め優先」にすると、pinned が真のメモを先頭に置き、その中と残りはそれぞれ指定の日時順に並べる。アーカイブするとき pinned は変更しない。アーカイブ済みのメモは NOT-BR-11 によりピン留めでも通常の一覧に出ない。 | https://usememos.com/docs/usage/memos 、https://usememos.com/docs/usage/views |
| NOT-BR-13 | 削除は物理削除で元に戻せない。メモを削除すると、そのメモに紐づく添付ファイル（実体を含む）も削除する。残したいが目に入れたくないメモはアーカイブする。 | https://usememos.com/docs/usage/attachments 、https://usememos.com/docs/usage/memos |
| NOT-BR-14 | 添付ファイルは 0 件または 1 件のメモに紐づく。複数のメモで共有しない。メモの添付を設定する操作は、指定した添付ファイル一覧で置き換え、外れた添付ファイルは未使用に戻る（削除はしない）。 | submodules/memos/docs/design/memos-export-format.md 、https://usememos.com/docs/usage/attachments |
| NOT-BR-15 | 未使用の添付ファイル（note_id が未設定）は一覧でき、個別または一括で削除できる。一括削除は未使用のものだけを対象にし、メモに紐づく添付ファイルには触れない。削除は元に戻せない。 | https://usememos.com/docs/usage/attachments |
| NOT-BR-16 | 添付ファイルは実体を保存する（STORED）か外部リンクだけを持つ（EXTERNAL）かのどちらか一方。STORED では sha256 と size を必ず記録する。EXTERNAL は保存容量に数えない。 | submodules/memos/docs/design/memos-export-format.md 、submodules/memos/docs/design/user-usage-limits.md |
| NOT-BR-17 | アップロード時、mime_type は呼び出し元の申告ではなくファイル内容から判定し直す。画像の EXIF 位置情報など撮影メタデータは保存前に取り除く。 | submodules/memos/docs/design/memos-export-format.md 、https://usememos.com/docs/usage/attachments |
| NOT-BR-18 | 本文中で notes が管理する添付画像を参照するとき、その添付ファイルは同じメモに紐づいていて、mime_type が `image/` で始まっていなければならない。満たさない本文の保存は拒否する。添付は保存と同じ操作の中で紐づけてよい。本文から画像の参照を消しても、添付の紐づけは外れない。 | submodules/memos/docs/design/memo-attachment-filters.md 、https://usememos.com/docs/usage/attachments |
| NOT-BR-19 | 添付ファイルの読み出しは、紐づくメモの公開範囲に従う。未使用の添付ファイルは所有者だけが読める。 | https://usememos.com/docs/usage/attachments |
| NOT-BR-20 | has_attachments は紐づく添付ファイルが 1 件以上あるとき真。has_image は本文に Markdown の画像記法（コード内を除く）があるか、mime_type が `image/` で始まる（大文字小文字を区別しない）添付が 1 件以上あるとき真。どちらも添付の追加・削除の直後から結果に反映する。 | submodules/memos/docs/design/memo-attachment-filters.md |
| NOT-BR-21 | 期間による絞り込み: from と to は date-time で、from 以上 to 未満（半開区間）。既定の基準は created_at で、time_field=updated_at で更新日時に切り替えられる。タイムゾーンなしの値は受け付けない。日付だけで指定したいときは呼び出し元が日付の 0 時（利用者のタイムゾーン）を date-time に変換して渡す。 | https://usememos.com/docs/usage/views 、https://usememos.com/docs/usage/memos |
| NOT-BR-22 | 全文検索は本文の部分一致で、大文字と小文字を区別しない。複数語は空白で区切り、すべてを含むメモが該当する（AND）。検索はタグ・期間・状態などの絞り込みと組み合わせられる。 | https://usememos.com/docs/usage/search-archive 、https://usememos.com/docs/usage/views |
| NOT-BR-23 | 一覧の並び順は created_at（または time_field で選んだ日時）の降順が既定で、昇順も選べる。同じ日時は id で順序を決める。ページングは不透明なページトークンで行い、続きがあるときだけ次のトークンを返す。1 ページの既定件数は 20、最大 100。 | https://usememos.com/docs/usage/memos 、https://usememos.com/docs/integrations/api-access |
| NOT-BR-24 | 作成日時と更新日時は作成時と部分更新時に呼び出し元が指定できる。作成時に指定がなければサーバー時刻にする。部分更新で updated_at を指定しなければ、他の項目を変えたときにサーバー時刻にする。作成時も更新時も updated_at は created_at 以上でなければならず、満たさない要求は拒否する。過去のレシートの購買日を created_at にしてよい。 | submodules/memos/docs/design/memos-export-format.md 、https://usememos.com/docs/usage/memos |
| NOT-BR-25 | 購買メモの記録（ingest_purchase）: 本文に購買タグ `#purchase`（または `#purchase/` で始まる子タグ）を必ず含める。含まない要求は入力エラーとして拒否し、サーバーは本文を書き換えない（NOT-BR-29）。分類用の子タグ（例: `#purchase/grocery`）は呼び出し元が本文に書く。レシート画像・PDF は同じ操作で添付する。created_at は購買日時。 | README.md §4.2、GitHub Issue #29 |
| NOT-BR-26 | external_ref の冪等性: 同じ所有者で同じ external_ref のメモがすでにあれば、新しく作らず既存のメモを返す（本文や添付は更新しない）。再送で添付ファイルだけが増えることもない。 | submodules/memos/docs/design/memos-export-format.md（UID をキーにした二重取り込みの防止）、README.md §4.2 |
| NOT-BR-27 | 文脈取得: 期間とタグ（NOT-BR-06・NOT-BR-21 と同じ規則）で対象を選び、created_at の昇順で返す。既定は NORMAL 状態だけ。max_notes（既定 50、最大 500）と max_bytes（本文の UTF-8 バイト数の合計、既定 65536）のどちらかに達したら打ち切り、truncated=true と打ち切らなければ返った件数を返す。1 件のメモを途中で切らない。添付ファイルは実体ではなくメタデータ（ファイル名・mime_type・ID）だけを返す。 | GitHub Issue #29、https://usememos.com/docs/integrations/mcp |
| NOT-BR-28 | 利用上限: メモの作成と本文を変える更新では本文のバイト数を、アップロードではファイル 1 件のサイズと保存容量の合計を、メモの作成ではメモ件数を検査する。値 0 は無制限。上限を超える操作は拒否し、どの上限か（metric）、上限値、現在値を返す。上限を下げても既存のデータは削除しない。待っても解消しないため再試行の目安は返さない。 | submodules/memos/docs/design/user-usage-limits.md |
| NOT-BR-29 | 本文は Markdown の文字列をそのまま保存し、サーバーは書き換えない（前後の空白の除去や改行の追加もしない）。HTML として解釈して保存することもしない。 | submodules/memos/docs/design/memos-export-format.md |

## LifePipe のワークフローとの関係

- ingest_purchase: 購買メモ・領収書ログの記録先。ゲートウェイは LLM で品目を振り分けた後、レシート画像のアップロードと、購買日時・本文（店名、合計金額、品目の要約、`#purchase` と分類用の子タグ）・external_ref を指定した購買メモの作成を notes に依頼する（NOT-UC-12）。notes は在庫や買い物リストを扱わず、pantry・inventory・wardrobe への登録はゲートウェイがそれぞれのサービスに並行して行う。
- get_morning_briefing: 必須の入力ではない。前日分のメモやピン留めしたメモを文脈取得（NOT-UC-13）で取り出し、ブリーフィングの補足に使える。
- prepare_outing: 直接は使わない。外出先でのメモの記録は通常のメモ作成（NOT-UC-01）で行う。
- LLM への文脈提供（ワークフロー共通）: 「先月の買い物」「#health の今週のログ」のように、期間とタグで絞ったメモを LLM の入力量に収まる形で渡す（NOT-UC-13）。

## API に必要なリソースと操作

| リソース | 操作 | 対応するユースケース ID | 備考 |
| --- | --- | --- | --- |
| notes | 一覧（フィルタ: q, tags, untagged, from, to, time_field, state, pinned, visibility, source, has_attachments, has_image, has_link, has_incomplete_tasks。並び: order=desc/asc, pinned_first。ページング: page_size, page_token） | NOT-UC-06, NOT-UC-07, NOT-UC-08 | state の既定は NORMAL。q は全文検索（NOT-BR-22）。 |
| notes | 作成（content, visibility, created_at, updated_at, attachment_ids, external_ref） | NOT-UC-01, NOT-UC-10 | tags と property はレスポンスで返す。external_ref が既存なら既存を返す（NOT-BR-26）。 |
| notes/{id} | 取得 | NOT-UC-02 | アーカイブ済みも返す。 |
| notes/{id} | 部分更新（content, visibility, created_at, updated_at, pinned, state） | NOT-UC-03, NOT-UC-05, NOT-UC-06 | 更新する項目だけを送る。state でアーカイブ・復元する。 |
| notes/{id} | 削除 | NOT-UC-04 | 紐づく添付も削除（NOT-BR-13）。 |
| notes/{id}/attachments | 一覧 / 置き換え（attachment_ids） | NOT-UC-10 | 置き換えで外れた添付は未使用に戻る（NOT-BR-14）。 |
| attachments | アップロード（multipart: file, filename, note_id 任意） / 外部リンクの登録（external_link, filename, mime_type） | NOT-UC-10, NOT-UC-12 | サイズ上限を検査（NOT-BR-28）。 |
| attachments | 一覧（フィルタ: unused, mime_type の前方一致。ページング） | NOT-UC-10, NOT-UC-11 | unused=true で未使用だけ。 |
| attachments/{id} | メタデータ取得 / 内容のダウンロード / ファイル名の変更 / 削除 | NOT-UC-10, NOT-UC-11 | ダウンロードは紐づくメモの公開範囲に従う（NOT-BR-19）。 |
| attachments:delete-unused | 未使用の一括削除 | NOT-UC-11 | 削除件数を返す。 |
| tags | 一覧（フィルタ: prefix。並び: name / note_count） | NOT-UC-09 | 読み取り専用（NOT-BR-05）。 |
| notes:context | 文脈取得（from, to, time_field, tags, q, max_notes, max_bytes） | NOT-UC-13 | 昇順で返し、truncated と total_count を含める（NOT-BR-27）。 |
| purchase-notes | 作成（purchased_at, content, receipt 添付ファイル（multipart または attachment_ids）, external_ref） | NOT-UC-12 | PRIVATE 固定、本文に `#purchase` がなければ入力エラー、source=INGEST_PURCHASE（NOT-BR-09, NOT-BR-25, NOT-BR-26）。作成された Note を返す。 |
| usage | 取得 | NOT-UC-14 | 後回し。 |
| usage-limits | 取得 / 置き換え | NOT-UC-14 | 後回し。 |

## 対象外

| 機能 | 理由 |
| --- | --- |
| コメント・スレッド | 1 人で使う Life OS では他者との議論がなく、メモの追記で足りる。 |
| リアクション | 他者からの反応を受ける用途がない。 |
| メンション・受信箱（通知） | 複数ユーザーが前提の機能で、通知は LifePipe 側の通知パイプラインが担う。 |
| 共有リンク | 外部公開の必要が当面なく、個人データの漏えい経路を増やす。必要になれば PUBLIC と併せて検討する。 |
| Space と公開範囲 SPACE、Space の招待・メンバー管理 | 単一ユーザー前提で共同領域が不要。 |
| メモ間の参照関係（Relation） | 検索とタグで当面の再発見は足りる。データ構造を増やさず MVP を小さく保つ。 |
| 保存済みフィルタ（View） | 絞り込み条件は LLM やゲートウェイ側で組み立てられる。 |
| CEL などの任意のフィルタ式 | MVP はクエリパラメータの固定の絞り込みで足りる。式の検証と DB ごとの翻訳の負担が大きい。 |
| Webhook | MVP ではゲートウェイから notes を呼ぶ方向だけで足り、notes から外部へ通知する用途がない。 |
| 位置情報・地図表示 | 位置は機微な個人データで、MVP のワークフローで使わない。 |
| エクスポート・インポート（ZIP） | バックアップはデータベースと添付ファイル保存先の退避で代替する。他インスタンスとの移行が当面ない。 |
| 音声の文字起こし | 外部 AI プロバイダへの依存が増える。LLM 連携はゲートウェイ側に置く。 |
| 利用状況・利用上限の取得と設定 API | 単一ユーザーでは既定値の固定で足りる。上限の検査自体（NOT-BR-28）は MVP で行う。 |
| 画像注釈（Markup）、画像としての書き出し、テーマ・表示設定 | 画面の機能で API の要件ではない。 |
| ユーザー管理・SSO・個人アクセストークン | 認証は LifePipe ゲートウェイの責務。 |

## 出典

ローカルファイル:

- submodules/memos/README.md
- submodules/memos/docs/design/README.md
- submodules/memos/docs/design/memo-attachment-filters.md
- submodules/memos/docs/design/memos-export-format.md
- submodules/memos/docs/design/multi-spaces.md
- submodules/memos/docs/design/user-usage-limits.md
- README.md（LifePipe、§2・§4）
- GitHub Issue #29「notes サービスを新規に作る」（スコープと完了条件）

URL:

- https://usememos.com/llms.txt
- https://usememos.com/docs/usage/memos
- https://usememos.com/docs/usage/tags
- https://usememos.com/docs/usage/search-archive
- https://usememos.com/docs/usage/sharing
- https://usememos.com/docs/usage/attachments
- https://usememos.com/docs/usage/reactions-comments
- https://usememos.com/docs/usage/views
- https://usememos.com/docs/integrations/webhooks
- https://usememos.com/docs/integrations/mcp
- https://usememos.com/docs/integrations/api-access
- https://usememos.com/docs/operations/architecture
- https://usememos.com/docs/configuration/storage
