import type {
  CalendarEvent,
  CalendarSource,
  CreateCalendarEventInput,
  PostConfig,
  SharedCalendarGateway,
} from '../../domain/calendar'

// 共有カレンダー（event / house）の読み書きは GAS の Web アプリに任せる（スクリプトの持ち主の権限で
// カレンダーと ROOM にアクセスできるため）。シークレットはサーバーでだけ付ける。
// GAS 側のコードは `services/gas/Code.js`
export class GasCalendarGateway implements SharedCalendarGateway, CalendarSource {
  constructor(
    private readonly webAppUrl: string,
    private readonly secret: string
  ) {}

  async create(input: CreateCalendarEventInput): Promise<CalendarEvent> {
    const data = await this.call<{ event?: unknown }>(
      new Request(this.webAppUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ secret: this.secret, ...input }),
      }),
      'イベント作成に失敗しました'
    )
    if (!data.event) throw new Error('イベント作成に失敗しました')
    return toEvent(data.event)
  }

  async fetchEvents(from: Date, to: Date): Promise<CalendarEvent[]> {
    const data = await this.call<{ events?: unknown }>(
      this.get({ action: 'events', from: from.toISOString(), to: to.toISOString() }),
      '予定の取得に失敗しました'
    )
    if (!Array.isArray(data.events)) throw new Error('予定の取得に失敗しました')
    return data.events.map(toEvent).filter((e) => e.id && e.startISO)
  }

  async fetchPostConfig(): Promise<PostConfig> {
    const data = await this.call<{ config?: { calendars?: unknown; rooms?: unknown } }>(
      this.get({ action: 'config' }),
      '設定の取得に失敗しました'
    )
    const calendars = Array.isArray(data.config?.calendars) ? data.config.calendars : []
    const rooms = Array.isArray(data.config?.rooms) ? data.config.rooms : []
    return {
      calendars: calendars.map(obj).map((c) => ({ key: str(c.key), name: str(c.name) })).filter((c) => c.key),
      rooms: rooms.map(obj).map((r) => ({ label: str(r.label), email: str(r.email) })).filter((r) => r.email),
    }
  }

  private get(params: Record<string, string>): Request {
    const url = new URL(this.webAppUrl)
    for (const [k, v] of Object.entries({ ...params, secret: this.secret })) url.searchParams.set(k, v)
    return new Request(url)
  }

  private async call<T>(req: Request, fallback: string): Promise<T> {
    // GAS の Web アプリは /exec でリダイレクトを挟む
    const res = await fetch(req, { redirect: 'follow' })
    const data = (await res.json().catch(() => null)) as ({ success?: boolean; error?: string } & T) | null
    if (!data?.success) throw new Error(data?.error ?? fallback)
    return data
  }
}

// GAS の返す値は信用しすぎず、欠けた項目は空文字で埋める
function toEvent(value: unknown): CalendarEvent {
  const raw = obj(value)
  return {
    id: str(raw.id),
    calendarName: str(raw.calendarName),
    title: str(raw.title),
    description: str(raw.description),
    location: str(raw.location),
    startISO: str(raw.startISO),
    endISO: str(raw.endISO),
    dateKey: str(raw.dateKey),
    startTime: str(raw.startTime),
    endTime: str(raw.endTime),
    displayDate: str(raw.displayDate),
    isAllDay: raw.isAllDay === true,
    color: str(raw.color),
    isRecurring: raw.isRecurring === true,
  }
}

function obj(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {}
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : ''
}
