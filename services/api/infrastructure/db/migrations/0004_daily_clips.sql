-- COLLEGE APP API — 日記クリップ（setlog 風の「毎日 2 秒」）とイベントクリップの紐付け
--
-- クリップは 2 種類:
--   日常用: daily_clips（1 人 1 日 1 本。撮り直しは上書き。本人だけが見られる）
--   イベント用: event_video_clips（0002_media.sql。イベント参加者みんなで撮り、みんなで見る）

-- 日常の 2 秒クリップ。clip_date は端末ローカルの日付（yyyy-MM-dd）
CREATE TABLE daily_clips (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  clip_date TEXT NOT NULL,
  r2_key TEXT NOT NULL,
  duration_ms INTEGER,
  caption TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (resident_id, clip_date)
);

-- カレンダー（Google カレンダー由来のイベント）と D1 の events を結びつける。
-- 繰り返し予定は同じ ID が日付違いで出てくるので、ID + 日付で一意にする
ALTER TABLE events ADD COLUMN calendar_event_id TEXT;
CREATE UNIQUE INDEX uniq_events_calendar_event ON events(calendar_event_id, event_date)
  WHERE calendar_event_id IS NOT NULL;
