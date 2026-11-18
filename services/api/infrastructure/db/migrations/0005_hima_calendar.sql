-- 旧 Supabase（public.availability / availability_invites / invite_groups / created_events）から移した既存機能
-- Supabase は廃止済み。データは引き継いでいない

PRAGMA foreign_keys = ON;

-- いまひま（「今ひま」の表明）。1人1件・期限付き。表明し直すと置き換わる
-- expires_at / created_at は ISO 8601（UTC, ミリ秒付き）で保存し、文字列比較で期限を判定する
CREATE TABLE hima_statuses (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL UNIQUE REFERENCES residents(id) ON DELETE CASCADE,
  message TEXT NOT NULL DEFAULT '',
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_hima_statuses_expires_at ON hima_statuses(expires_at);

-- 表明への「誘う」。表明を消す（置き換える）と誘いも消える
CREATE TABLE hima_invites (
  id TEXT PRIMARY KEY,
  status_id TEXT NOT NULL REFERENCES hima_statuses(id) ON DELETE CASCADE,
  inviter_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  message TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX idx_hima_invites_status_id ON hima_invites(status_id, created_at);

-- カレンダー招待のグループ（よく招待するメンバーのメールアドレスの組）。本人だけが見る
CREATE TABLE invite_groups (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  emails TEXT NOT NULL, -- JSON 配列
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_invite_groups_owner_id ON invite_groups(owner_id);

-- 誰がどのカレンダーイベントを作ったか（Calendar の MY EVENT 用）。event_id は Google カレンダーのイベント ID
CREATE TABLE created_calendar_events (
  event_id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_created_calendar_events_resident_id ON created_calendar_events(resident_id);
