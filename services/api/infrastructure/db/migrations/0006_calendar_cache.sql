-- カレンダーの予定のキャッシュ（旧 EventCache スプレッドシートの置き換え）。
-- 正は Google カレンダー。Cron Trigger が GAS 経由で定期的に取り直し、取得範囲内を丸ごと入れ替える。
-- アプリのイベント一覧はここを読むだけ（GAS は遅いので一覧表示のたびには呼ばない）

-- 列は iOS の CalendarEvent と同じ。event_id は Google カレンダーのイベント ID で、
-- 繰り返し予定は同じ ID が回ごとに現れるので、主キーは (event_id, start_iso)
CREATE TABLE calendar_events (
  event_id TEXT NOT NULL,
  start_iso TEXT NOT NULL,
  end_iso TEXT NOT NULL,
  calendar_name TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  date_key TEXT NOT NULL,      -- yyyy-MM-dd（JST）
  start_time TEXT NOT NULL,    -- HH:mm（JST）。終日は ''
  end_time TEXT NOT NULL,
  display_date TEXT NOT NULL,  -- M/d
  is_all_day INTEGER NOT NULL DEFAULT 0,
  is_recurring INTEGER NOT NULL DEFAULT 0,
  color TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (event_id, start_iso)
);
CREATE INDEX idx_calendar_events_start_iso ON calendar_events(start_iso);

-- 同期の状態などの小さな値。
--   last_sync: 最後に同期できた時刻（ISO 8601）
--   post_config: 投稿先の選択肢（カレンダー名・ROOM 一覧）の JSON
CREATE TABLE calendar_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
