-- COLLEGE APP API — 写真・イベント動画クリップ・思い出ビデオ
-- ストレージ本体は Cloudflare R2 に置き、D1 には r2_key（オブジェクトキー）だけを持つ

-- イベント（最小限）。Calendar 機能本体（Google Sheets/GAS 連携）の移行は別途。
-- 動画クリップ・思い出ビデオの紐付け先として先行して用意する。
CREATE TABLE events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  event_date TEXT NOT NULL,
  created_by_resident_id TEXT REFERENCES residents(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- カレッジ生の写真（顔写真 / 紙の図鑑のスキャン画像 / 自分に関連する写真）
CREATE TABLE resident_photos (
  id TEXT PRIMARY KEY,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('face', 'paper_directory', 'gallery')),
  r2_key TEXT NOT NULL,
  caption TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_resident_photos_resident_id ON resident_photos(resident_id, kind);

-- イベントごとの短尺動画クリップ（setlog的な2秒動画。1人1イベント複数投稿可）
CREATE TABLE event_video_clips (
  id TEXT PRIMARY KEY,
  event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  resident_id TEXT NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  r2_key TEXT NOT NULL,
  duration_ms INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_event_video_clips_event_id ON event_video_clips(event_id);

-- イベントの思い出ビデオ（クリップ結合 + 音楽）の生成ジョブ
-- 音源は居住者がアップロードした MP3（著作権的に問題ないもの）のみを使う。YouTube からの音声抽出は行わない。
-- 実際の合成基盤（外部動画合成API等）は未確定。README 参照
CREATE TABLE event_memory_videos (
  id TEXT PRIMARY KEY,
  event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  requested_by_resident_id TEXT NOT NULL REFERENCES residents(id),
  music_r2_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  output_r2_key TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  completed_at TEXT
);
CREATE INDEX idx_event_memory_videos_event_id ON event_memory_videos(event_id);
