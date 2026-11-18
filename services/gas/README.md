# services/gas

共有 Google カレンダー（000_イベントカレンダー / 001_ハウス・委員会）と ROOM を読み書きする
Google Apps Script の Web アプリ。呼び出し元は新 API（[`services/api`](../api)）だけ。

| 呼び方 | 用途 | 新 API 側 |
| --- | --- | --- |
| `GET ?action=events&from=&to=&secret=` | 予定の一覧（最大 120 日分） | Cron Trigger が 15 分ごとに呼んで D1 に入れる |
| `GET ?action=config&secret=` | 投稿先カレンダー名と ROOM 一覧 | 同上 |
| `POST {secret, calendarKey, title, …}` | イベント作成（ROOM はゲスト追加で予約） | `POST /calendar-events` |

スクリプトの持ち主（共有カレンダーの「予定の変更」権限と ROOM の予約権限を持つ hlab.college のアカウント）の権限で動く。
以前あったスプレッドシート（EventCache）への書き出しは廃止した。

## 配備（手作業）

Apps Script はこのリポジトリから自動では配備されない。`Code.js` を変えたら次の手順で反映する。

1. 既存の Apps Script プロジェクトを開き、`コード.gs` の中身を `Code.js` で丸ごと置き換えて保存
2. 「プロジェクトの設定」→「スクリプト プロパティ」に `POST_SECRET` を追加
   （値は新 API の `wrangler secret put GAS_POST_SECRET` と同じ。シークレットはコードに書かない）
3. 「デプロイ」→「デプロイを管理」→ 既存のデプロイを編集 → バージョン「新バージョン」→「デプロイ」
   （既存のデプロイを編集すれば URL は変わらない。新しく作る場合は「次のユーザーとして実行: 自分」
   「アクセスできるユーザー: 全員」にする。Workers は Google にログインせずに呼ぶため。守りはシークレット）
4. 旧版からの移行時だけ: エディタで `removeOldTriggers` を一度実行し、スプレッドシート同期のトリガーを消す

カレンダーや ROOM を増やすときは `listAllCalendarIds` を実行して ID を確認し、`POST_CALENDARS` / `ROOMS` に足す。
