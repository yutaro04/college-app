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
