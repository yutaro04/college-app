-- カレンダーの予定の論理削除。
-- 同期で消えた予定は行を消さずに deleted_at を入れる（物理削除はインデックスの分まで書き込み行数に数えられるため）。
-- 同期の範囲（過去 30 日）より古い予定は同期で触らず、そのまま残す（日記の「イベント」の過去分）
ALTER TABLE calendar_events ADD COLUMN deleted_at TEXT;
