// カレンダー（旧 Next.js の /api/events・/api/events/config・/api/events/create を移したもの）。
// 正は Google カレンダー。共有カレンダーの読み書きは GAS の Web アプリ経由で、一覧は D1 にキャッシュして返す

export type CalendarKey = 'event' | 'house' | 'private'

export interface CreateCalendarEventInput {
  calendarKey: CalendarKey
  title: string
  description: string
  location: string
  roomEmail: string
  attendees: string[]
  isAllDay: boolean
  dateKey: string // yyyy-MM-dd
  startISO: string
  endISO: string
}

// iOS の `CalendarEvent` と同じ形（GAS が返すものと揃える）
export interface CalendarEvent {
  id: string
  calendarName: string
  title: string
  description: string
  location: string
  startISO: string
  endISO: string
  dateKey: string
  startTime: string
  endTime: string
  displayDate: string
  isAllDay: boolean
  color: string
  isRecurring: boolean
}

export interface CalendarOption {
  key: string
  name: string
}

export interface RoomOption {
  label: string
  email: string
}

// 投稿フォームの選択肢（投稿先カレンダーと ROOM）
export interface PostConfig {
  calendars: CalendarOption[]
  rooms: RoomOption[]
}

// 共有カレンダー（event / house）への作成。GAS の Web アプリが Google カレンダーに書き込む
export interface SharedCalendarGateway {
  create(input: CreateCalendarEventInput): Promise<CalendarEvent>
}

// 共有カレンダーの読み取り。GAS の Web アプリがカレンダーから直接取る（遅いので Cron で呼んで D1 に溜める）
export interface CalendarSource {
  fetchEvents(from: Date, to: Date): Promise<CalendarEvent[]>
  fetchPostConfig(): Promise<PostConfig>
}

// 予定のキャッシュ（D1）
export interface CalendarCacheRepository {
  // [from, to) に始まる予定を `events` と同じにする（1 トランザクション）。
  // 差分だけを書く。消えた予定は論理削除（D1 の書き込み行数を抑えるため）。範囲より古い予定には触らない。
  // 何か変わったときだけ（と初回だけ）版を `syncedAt` に進める
  syncRange(from: string, to: string, events: CalendarEvent[], syncedAt: string): Promise<void>
  // 1 件だけ追加・上書きし、版を `changedAt` に進める（共有カレンダーに作った直後）
  upsert(event: CalendarEvent, changedAt: string): Promise<void>
  // 開始が [from, to) の、削除されていない予定（開始日時順）
  list(from: string, to: string): Promise<CalendarEvent[]>
  // 予定のデータの版（最後に中身が変わった時刻）。アプリはこれでキャッシュが古いかを判断する。未同期なら null
  version(): Promise<string | null>
  savePostConfig(config: PostConfig): Promise<void>
  loadPostConfig(): Promise<PostConfig | null>
}

// 本人の Google カレンダー（primary）への作成。アプリから受け取った本人の access token を使う
export interface PrivateCalendarGateway {
  create(googleAccessToken: string, input: CreateCalendarEventInput): Promise<{ id: string }>
}

export interface CreatedCalendarEventRepository {
  record(eventId: string, residentId: string): Promise<void>
  listIds(residentId: string): Promise<string[]>
}
