-- COLLEGE APP API — 交流機能
-- おすすめの店 / 気になる（マチアプ風の相互いいね） / 「〇〇あったら誘って」 /
-- 空き時間 / ひま募集 / 匿名文通

-- おすすめの店（図鑑の個人ページに表示。全員分を横断して一覧もできる）
CREATE TABLE resident_recommendations (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  genre TEXT NOT NULL CHECK (genre IN ('cafe', 'restaurant', 'bar', 'shop', 'other')),
  area TEXT,
  comment TEXT,
  url TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_resident_recommendations_resident_id ON resident_recommendations(resident_id);
CREATE INDEX idx_resident_recommendations_genre ON resident_recommendations(genre);

-- 気になる（マチアプ風）。カードを左右に振り分けた結果を 1 ペア 1 行で持つ。
-- 双方が 'like' のときだけマッチとして互いに表示する（片思いの相手は明かさない）。
-- topic は「何に興味を持ったか」（相手の属性タグの値など）。マッチ後に相手へ見せる
CREATE TABLE resident_likes (
  from_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  to_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('like', 'pass')),
  topic TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (from_resident_id, to_resident_id),
  CHECK (from_resident_id != to_resident_id)
);
CREATE INDEX idx_resident_likes_to ON resident_likes(to_resident_id, kind);

-- 「〇〇あったら誘って」
CREATE TABLE invite_wishes (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_invite_wishes_resident_id ON invite_wishes(resident_id);

-- 「誘って」に対して実際に誘ったもの
CREATE TABLE invite_wish_invitations (
  id TEXT PRIMARY KEY,
  wish_id TEXT NOT NULL REFERENCES invite_wishes(id) ON DELETE CASCADE,
  inviter_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_invite_wish_invitations_wish_id ON invite_wish_invitations(wish_id);

-- 空き時間（本人が登録する。個人ページで他の人から見える）
-- 将来 Google カレンダーの free/busy から自動生成する場合も、このテーブルに書き込む想定
CREATE TABLE resident_free_slots (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK (ends_at > starts_at)
);
CREATE INDEX idx_resident_free_slots_range ON resident_free_slots(starts_at, ends_at);
CREATE INDEX idx_resident_free_slots_resident_id ON resident_free_slots(resident_id, starts_at);

-- ひま募集（「この時間空いてるから誰か〇〇しよう」）
-- いま暇な人の「表明」は既存の Supabase availability のまま（移行は別途）。こちらは時間指定で人を集めるもの
CREATE TABLE hima_gatherings (
  id TEXT PRIMARY KEY,
  host_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  location TEXT,
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  capacity INTEGER CHECK (capacity IS NULL OR capacity > 0),
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  cancelled_at TEXT,
  CHECK (ends_at > starts_at)
);
CREATE INDEX idx_hima_gatherings_starts_at ON hima_gatherings(starts_at);

CREATE TABLE hima_gathering_participants (
  gathering_id TEXT NOT NULL REFERENCES hima_gatherings(id) ON DELETE CASCADE,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (gathering_id, resident_id)
);

-- 匿名文通。手紙を出すとサーバーがランダムに相手を選び、互いにペンネームだけが見える。
-- *_resident_id は API レスポンスに絶対に含めないこと（匿名性の担保はサーバー側の責務）
CREATE TABLE pen_pal_threads (
  id TEXT PRIMARY KEY,
  starter_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  partner_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  starter_alias TEXT NOT NULL,
  partner_alias TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  closed_at TEXT,
  CHECK (starter_resident_id != partner_resident_id)
);
CREATE INDEX idx_pen_pal_threads_starter ON pen_pal_threads(starter_resident_id);
CREATE INDEX idx_pen_pal_threads_partner ON pen_pal_threads(partner_resident_id);

CREATE TABLE pen_pal_letters (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL REFERENCES pen_pal_threads(id) ON DELETE CASCADE,
  sender_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  read_at TEXT
);
CREATE INDEX idx_pen_pal_letters_thread_id ON pen_pal_letters(thread_id, created_at);

-- 匿名なので、嫌な思いをしたときの通報窓口を用意しておく（運営が確認する。管理画面は別途）
CREATE TABLE pen_pal_reports (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL REFERENCES pen_pal_threads(id) ON DELETE CASCADE,
  reporter_resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
