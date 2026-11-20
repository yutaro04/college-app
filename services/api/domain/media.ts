import type { ResidentRef } from './resident'


export type ResidentPhotoKind = 'face' | 'paper_directory' | 'gallery'

export interface ResidentPhoto {
  id: string
  residentId: string
  kind: ResidentPhotoKind
  r2Key: string
  caption: string | null
  sortOrder: number
  createdAt: string
}

export interface Event {
  id: string
  title: string
  eventDate: string
  /** カレンダー（Google カレンダー由来）のイベント ID。カレンダー外で作ったイベントは null */
  calendarEventId: string | null
  createdByResidentId: string | null
  createdAt: string
}

export interface EventVideoClip {
  id: string
  eventId: string
  residentId: string
  r2Key: string
  durationMs: number | null
  createdAt: string
}

export type MemoryVideoStatus = 'pending' | 'processing' | 'completed' | 'failed'

export interface EventMemoryVideo {
  id: string
  eventId: string
  requestedByResidentId: string
  musicR2Key: string
  status: MemoryVideoStatus
  outputR2Key: string | null
  errorMessage: string | null
  createdAt: string
  completedAt: string | null
}

/** 日記（setlog 風）の 1 日 1 本の 2 秒クリップ。本人だけが見られる */
export interface DailyClip {
  id: string
  residentId: string
  /** 端末ローカルの日付 yyyy-MM-dd */
  clipDate: string
  r2Key: string
  durationMs: number | null
  caption: string | null
  createdAt: string
  updatedAt: string
}

// ── イベントの 2 秒クリップ（日記の「イベント」。参加者みんなで撮ってみんなで見る） ──

/** 1 本あたりの上限サイズ。アプリは 2 秒・1080p に切り出してから送る（数 MB）ので余裕を持たせている */
export const EVENT_CLIP_MAX_BYTES = 30 * 1024 * 1024
/** 1 人が 1 イベントに投稿できる本数 */
export const EVENT_CLIPS_PER_RESIDENT_MAX = 20
export const EVENT_CLIP_CONTENT_TYPES = ['video/mp4', 'video/quicktime']

/** 一覧用。クリップ数を添える */
export interface EventSummary {
  id: string
  title: string
  eventDate: string
  calendarEventId: string | null
  clipCount: number
}

/** API が返すクリップ。動画本体は `GET /events/:eventId/clips/:clipId/file` で取る */
export interface EventClipView {
  id: string
  eventId: string
  residentId: string
  author: ResidentRef
  durationMs: number | null
  createdAt: string
}

export interface EventRepository {
  find(id: string): Promise<Event | null>
  /** calendar_event_id + event_date で探す */
  findByCalendarEvent(calendarEventId: string, eventDate: string): Promise<Event | null>
  /** 同時に作られても 1 行になる（uniq_events_calendar_event）。作成済みならそれを返す */
  findOrCreateForCalendarEvent(calendarEventId: string, eventDate: string, title: string, residentId: string): Promise<Event>
  /** カレンダーのキャッシュ（calendar_events）からタイトルを引く。無ければ null */
  calendarEventTitle(calendarEventId: string, eventDate: string): Promise<string | null>
  listWithClipCounts(from: string, to: string): Promise<EventSummary[]>
}

export interface EventClipRepository {
  find(id: string): Promise<EventClipView | null>
  /** r2_key を含む生の行（ファイル取得・削除用） */
  findRow(id: string): Promise<EventVideoClip | null>
  list(eventId: string): Promise<EventClipView[]>
  countByResident(eventId: string, residentId: string): Promise<number>
  create(clip: Omit<EventVideoClip, 'createdAt'>): Promise<void>
  delete(id: string): Promise<void>
}

/** R2 などのオブジェクトストレージ */
export interface MediaObject {
  body: ReadableStream
  size: number
  contentType: string
  etag: string
}

export interface MediaStorage {
  put(key: string, body: ArrayBuffer | ReadableStream, contentType: string): Promise<void>
  get(key: string): Promise<MediaObject | null>
  delete(key: string): Promise<void>
}
