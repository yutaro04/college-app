import type { CalendarCacheRepository, CalendarEvent, PostConfig } from '../../domain/calendar'

interface Row {
  event_id: string
  start_iso: string
  end_iso: string
  calendar_name: string
  title: string
  description: string
  location: string
  date_key: string
  start_time: string
  end_time: string
  display_date: string
  is_all_day: number
  is_recurring: number
  color: string
}

const UPSERT_SQL = `INSERT INTO calendar_events
  (event_id, start_iso, end_iso, calendar_name, title, description, location,
   date_key, start_time, end_time, display_date, is_all_day, is_recurring, color)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT (event_id, start_iso) DO UPDATE SET
    end_iso = excluded.end_iso, calendar_name = excluded.calendar_name, title = excluded.title,
    description = excluded.description, location = excluded.location, date_key = excluded.date_key,
    start_time = excluded.start_time, end_time = excluded.end_time, display_date = excluded.display_date,
    is_all_day = excluded.is_all_day, is_recurring = excluded.is_recurring, color = excluded.color`

const META_SQL = `INSERT INTO calendar_meta (key, value, updated_at) VALUES (?, ?, datetime('now'))
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`

export class D1CalendarCacheRepository implements CalendarCacheRepository {
  constructor(private readonly db: D1Database) {}

  async replaceBefore(before: string, events: CalendarEvent[], syncedAt: string): Promise<void> {
    // batch は 1 トランザクションで走るので、途中で失敗しても一覧が空になることはない
    await this.db.batch([
      this.db.prepare('DELETE FROM calendar_events WHERE start_iso < ?').bind(before),
      ...events.map((e) => this.bindEvent(e)),
      this.db.prepare(META_SQL).bind('last_sync', syncedAt),
    ])
  }

  async upsert(event: CalendarEvent): Promise<void> {
    await this.bindEvent(event).run()
  }

  async list(): Promise<CalendarEvent[]> {
    const { results } = await this.db
      .prepare('SELECT * FROM calendar_events ORDER BY start_iso, event_id')
      .all<Row>()
    return results.map(toEvent)
  }

  async lastSync(): Promise<string | null> {
    return this.meta('last_sync')
  }

  async savePostConfig(config: PostConfig): Promise<void> {
    await this.db.prepare(META_SQL).bind('post_config', JSON.stringify(config)).run()
  }

  async loadPostConfig(): Promise<PostConfig | null> {
    const value = await this.meta('post_config')
    return value ? (JSON.parse(value) as PostConfig) : null
  }

  private async meta(key: string): Promise<string | null> {
    const row = await this.db.prepare('SELECT value FROM calendar_meta WHERE key = ?').bind(key).first<{ value: string }>()
    return row?.value ?? null
  }

  private bindEvent(e: CalendarEvent): D1PreparedStatement {
    return this.db
      .prepare(UPSERT_SQL)
      .bind(
        e.id, e.startISO, e.endISO, e.calendarName, e.title, e.description, e.location,
        e.dateKey, e.startTime, e.endTime, e.displayDate, e.isAllDay ? 1 : 0, e.isRecurring ? 1 : 0, e.color
      )
  }
}

function toEvent(r: Row): CalendarEvent {
  return {
    id: r.event_id,
    calendarName: r.calendar_name,
    title: r.title,
    description: r.description,
    location: r.location,
    startISO: r.start_iso,
    endISO: r.end_iso,
    dateKey: r.date_key,
    startTime: r.start_time,
    endTime: r.end_time,
    displayDate: r.display_date,
    isAllDay: r.is_all_day === 1,
    color: r.color,
    isRecurring: r.is_recurring === 1,
  }
}
