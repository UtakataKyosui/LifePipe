# ドメイン要件

LifePipe で新規に開発する6つのドメインサービスの要件。外部 API（`openapi/openapi.yaml`）は、この要件を根拠に定義する。

| ドメイン | ファイル | ID の接頭辞 | 要件の参考元 | 参考元のライセンス |
| --- | --- | --- | --- | --- |
| 物品・固定資産 | [inventory.md](inventory.md) | INV | Homebox | AGPL-3.0 |
| 衣服・ワードローブ | [wardrobe.md](wardrobe.md) | WRD | Wardrowbe | MIT |
| 食材・日用品の在庫 | [pantry.md](pantry.md) | PAN | Grocy | MIT |
| タスク・定期家事 | [tasks.md](tasks.md) | TSK | Vikunja | AGPL-3.0 |
| メモ・ログ | [notes.md](notes.md) | NOT | Memos | MIT |
| 固定費・サブスクリプション | [subscriptions.md](subscriptions.md) | SUB | Wallos | GPL-3.0 |

## クリーンルームの規約

参考元のソースコードは読まない。要件は次の情報だけから汲み取る。

- 参考元の README、利用者向けドキュメント、CHANGELOG
- 参考元の公式サイトと公式ドキュメント

ソースコード、SQL・マイグレーション、`.proto`、upstream の OpenAPI / Swagger 定義、テストコード、翻訳ファイル、実装の内部を説明する開発者向けドキュメントは使わない。文章や画面の文言はコピーせず、日本語で言い換える。

参考元の資料に記述がなく LifePipe 側で決めたルールは、各ドキュメントの出典欄に「LifePipe」と書いてある。

## 章立てと ID

各ドキュメントは同じ章立てで書く。

1. 責務
2. 参考元の構成
3. エンティティ
4. ユースケース（`<接頭辞>-UC-nn`、優先度は MVP / 後回し）
5. 業務ルール（`<接頭辞>-BR-nn`）
6. LifePipe のワークフローとの関係
7. API に必要なリソースと操作
8. 対象外
9. 出典
