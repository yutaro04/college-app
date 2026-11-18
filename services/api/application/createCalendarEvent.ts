import type {
  CalendarCacheRepository,
  CalendarEvent,
  CreateCalendarEventInput,
  CreatedCalendarEventRepository,
  PrivateCalendarGateway,
  SharedCalendarGateway,
} from '../domain/calendar'
import { UseCaseError } from './errors'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const PRIVATE_COLOR = '#4285F4'

// 招待先メールアドレスの検証・重複除去（不正な値は無視する）
function sanitizeAttendees(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  const emails = raw.filter((e): e is string => typeof e === 'string' && EMAIL_RE.test(e.trim())).map((e) => e.trim())
  return [...new Set(emails)].slice(0, 50)
}

function str(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

// 入力の検証（旧 Next.js の /api/events/create と同じ規則）
export function parseCreateCalendarEventInput(body: Record<string, unknown>): CreateCalendarEventInput {
  const title = str(body.title)
  if (!title) throw new UseCaseError(400, 'タイトルは必須です')
  const calendarKey = body.calendarKey
  if (calendarKey !== 'event' && calendarKey !== 'house' && calendarKey !== 'private') {
    throw new UseCaseError(400, 'カレンダーの選択が不正です')
  }
  const isAllDay = body.isAllDay === true
  const dateKey = str(body.dateKey)
  const startISO = str(body.startISO)
  const endISO = str(body.endISO)
  if (isAllDay) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) throw new UseCaseError(400, '日付が不正です')
  } else {
    const start = new Date(startISO)
    const end = new Date(endISO)
    if (isNaN(start.getTime()) || isNaN(end.getTime()) || end <= start) {
      throw new UseCaseError(400, '開始/終了時刻が不正です')
    }
  }
  return {
    calendarKey,
    title,
    description: str(body.description),
    location: str(body.location),
    roomEmail: str(body.roomEmail),
    attendees: sanitizeAttendees(body.attendees),
    isAllDay,
    dateKey,
    startISO,
    endISO,
  }
}

export async function createCalendarEvent(
  deps: {
    shared: SharedCalendarGateway | null
    private: PrivateCalendarGateway
    created: CreatedCalendarEventRepository
    cache: CalendarCacheRepository
  },
  residentId: string,
  input: CreateCalendarEventInput,
  googleAccessToken: string | null
): Promise<CalendarEvent> {
  let event: CalendarEvent
  if (input.calendarKey === 'private') {
    if (!googleAccessToken) {
      throw new UseCaseError(400, 'Googleカレンダーとの連携が必要です。一度ログアウトして再ログインしてください')
    }
    const created = await deps.private.create(googleAccessToken, input).catch((e: unknown) => {
      throw new UseCaseError(502, e instanceof Error ? e.message : 'イベント作成に失敗しました')
    })
    event = privateEvent(created.id, input)
  } else {
    if (!deps.shared) throw new UseCaseError(500, 'サーバー設定が不足しています (GAS_WEBAPP_URL / GAS_POST_SECRET)')
    event = await deps.shared.create(input).catch((e: unknown) => {
      throw new UseCaseError(502, e instanceof Error ? e.message : 'カレンダーサービスへの接続に失敗しました')
    })
    // 次の定期同期を待たずに一覧へ出す。失敗しても次の同期で入る
    await deps.cache.upsert(event).catch((e) => console.error('calendar_events', e))
  }
  // MY EVENT 用の記録。失敗しても作成自体は成功扱いにする
  await deps.created.record(event.id, residentId).catch((e) => console.error('created_calendar_events', e))
  return event
}

function privateEvent(id: string, input: CreateCalendarEventInput): CalendarEvent {
  const [, m, d] = input.dateKey.split('-')
  return {
    id,
    calendarName: 'プライベート',
    title: input.title,
    description: input.description,
    location: input.location,
    startISO: input.isAllDay ? '' : input.startISO,
    endISO: input.isAllDay ? '' : input.endISO,
    dateKey: input.dateKey,
    startTime: input.isAllDay ? '' : jstHHmm(input.startISO),
    endTime: input.isAllDay ? '' : jstHHmm(input.endISO),
    displayDate: m && d ? `${Number(m)}/${Number(d)}` : '',
    isAllDay: input.isAllDay,
    color: PRIVATE_COLOR,
    isRecurring: false,
  }
}

function jstHHmm(iso: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Tokyo',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(iso))
}
