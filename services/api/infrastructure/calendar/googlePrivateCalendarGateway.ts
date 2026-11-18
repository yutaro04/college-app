import type { CreateCalendarEventInput, PrivateCalendarGateway } from '../../domain/calendar'

// 本人の Google カレンダー（primary）に作成する。access token は iOS がログイン時に得た本人のもの
// （calendar.events スコープ）。サーバーは Google のリフレッシュトークンを預からない
export class GooglePrivateCalendarGateway implements PrivateCalendarGateway {
  async create(googleAccessToken: string, input: CreateCalendarEventInput): Promise<{ id: string }> {
    const body: Record<string, unknown> = { summary: input.title }
    if (input.description) body.description = input.description
    if (input.location) body.location = input.location
    if (input.isAllDay) {
      body.start = { date: input.dateKey }
      // 終日イベントの終了日は排他的
      body.end = { date: addDays(input.dateKey, 1) }
    } else {
      body.start = { dateTime: input.startISO }
      body.end = { dateTime: input.endISO }
    }
    const guests = [...new Set([...input.attendees, input.roomEmail].filter(Boolean))]
    if (guests.length > 0) body.attendees = guests.map((email) => ({ email }))

    const res = await fetch('https://www.googleapis.com/calendar/v3/calendars/primary/events', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${googleAccessToken}` },
      body: JSON.stringify(body),
    })
    const data = (await res.json().catch(() => null)) as { id?: string; error?: { message?: string } } | null
    if (!res.ok || !data?.id) {
      throw new Error(data?.error?.message ?? 'Googleカレンダーへのイベント作成に失敗しました')
    }
    return { id: data.id }
  }
}

function addDays(dateKey: string, days: number): string {
  const [y, m, d] = dateKey.split('-').map(Number)
  const date = new Date(Date.UTC(y, m - 1, d + days))
  return date.toISOString().slice(0, 10)
}
