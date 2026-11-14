-- COLLEGE APP API — Cloudflare D1 (SQLite) initial schema
-- カレッジ生図鑑 / 属性 / コーヒーチャット申請

PRAGMA foreign_keys = ON;

-- 認証ユーザー（Google OAuth）
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  google_sub TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- セッション（Cookie に持つ session id に対応）
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);

-- カレッジ生（居住者）プロフィール
CREATE TABLE residents (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 属性カテゴリ（趣味・興味・専門分野・大学・会社。将来カテゴリを増やせるようテーブル化）
CREATE TABLE attribute_categories (
  id TEXT PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);

INSERT INTO attribute_categories (id, key, label, sort_order) VALUES
  ('cat_hobby', 'hobby', '趣味', 1),
  ('cat_interest', 'interest', '興味', 2),
  ('cat_specialty', 'specialty', '専門分野', 3),
  ('cat_university', 'university', '大学', 4),
  ('cat_company', 'company', '会社', 5);

-- 属性（タグ）本体。ユーザーが自由に追加できるフリータグ
-- normalized_value で表記ゆれ（大文字小文字・前後空白）を吸収して重複を防ぐ
CREATE TABLE attributes (
  id TEXT PRIMARY KEY,
  category_id TEXT NOT NULL REFERENCES attribute_categories(id),
  value TEXT NOT NULL,
  normalized_value TEXT NOT NULL,
  created_by_resident_id TEXT REFERENCES residents(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (category_id, normalized_value)
);
CREATE INDEX idx_attributes_category_id ON attributes(category_id);

-- カレッジ生 ↔ 属性（多対多）
CREATE TABLE resident_attributes (
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  attribute_id TEXT NOT NULL REFERENCES attributes(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (resident_id, attribute_id)
);
CREATE INDEX idx_resident_attributes_attribute_id ON resident_attributes(attribute_id);

-- コーヒーチャット（1on1）申請
CREATE TABLE coffee_chat_requests (
  id TEXT PRIMARY KEY,
  requester_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  recipient_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT,
  CHECK (requester_id != recipient_id)
);
CREATE INDEX idx_coffee_chat_requester ON coffee_chat_requests(requester_id, status);
CREATE INDEX idx_coffee_chat_recipient ON coffee_chat_requests(recipient_id, status);
-- 同じ相手への pending な申請の重複を防ぐ
CREATE UNIQUE INDEX uniq_coffee_chat_pending_pair ON coffee_chat_requests(requester_id, recipient_id) WHERE status = 'pending';
