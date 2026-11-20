import type {
  Event,
  EventClipRepository,
  EventClipView,
  EventRepository,
  EventSummary,
  EventVideoClip,
} from '../../domain/media'

interface EventRow {
  id: string
  title: string
  event_date: string
  calendar_event_id: string | null
  created_by_resident_id: string | null
  created_at: string
}

const toEvent = (r: EventRow): Event => ({
  id: r.id,
  title: r.title,
  eventDate: r.event_date,
  calendarEventId: r.calendar_event_id,
  createdByResidentId: r.created_by_resident_id,
  createdAt: r.created_at,
})

export class D1EventRepository implements EventRepository {
  constructor(private readonly db: D1Database) {}

  async find(id: string): Promise<Event | null> {
    const row = await this.db.prepare('SELECT * FROM events WHERE id = ?').bind(id).first<EventRow>()
    return row ? toEvent(row) : null
  }

  async findByCalendarEvent(calendarEventId: string, eventDate: string): Promise<Event | null> {
    const row = await this.db
      .prepare('SELECT * FROM events WHERE calendar_event_id = ? AND event_date = ?')
      .bind(calendarEventId, eventDate)
      .first<EventRow>()
    return row ? toEvent(row) : null
  }

  async findOrCreateForCalendarEvent(
    calendarEventId: string,
    eventDate: string,
    title: string,
    residentId: string
  ): Promise<Event> {
    // 同時に作られたら一意インデックス（uniq_events_calendar_event）で片方が無視される
    await this.db
      .prepare(
        `INSERT OR IGNORE INTO events (id, title, event_date, calendar_event_id, created_by_resident_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(crypto.randomUUID(), title, eventDate, calendarEventId, residentId, new Date().toISOString())
      .run()
    return (await this.findByCalendarEvent(calendarEventId, eventDate))!
  }

  async calendarEventTitle(calendarEventId: string, eventDate: string): Promise<string | null> {
    const row = await this.db
      .prepare('SELECT title FROM calendar_events WHERE event_id = ? AND date_key = ? AND deleted_at IS NULL LIMIT 1')
      .bind(calendarEventId, eventDate)
      .first<{ title: string }>()
    return row?.title ?? null
  }

  async listWithClipCounts(from: string, to: string): Promise<EventSummary[]> {
    const { results } = await this.db
      .prepare(
        `SELECT e.id, e.title, e.event_date, e.calendar_event_id, COUNT(c.id) AS clip_count
           FROM events e
           LEFT JOIN event_video_clips c ON c.event_id = e.id
          WHERE e.event_date BETWEEN ? AND ?
          GROUP BY e.id
          ORDER BY e.event_date DESC`
      )
      .bind(from, to)
      .all<{ id: string; title: string; event_date: string; calendar_event_id: string | null; clip_count: number }>()
    return results.map((r) => ({
      id: r.id,
      title: r.title,
      eventDate: r.event_date,
      calendarEventId: r.calendar_event_id,
      clipCount: r.clip_count,
    }))
  }
}

interface ClipRow {
  id: string
  event_id: string
  resident_id: string
  r2_key: string
  duration_ms: number | null
  created_at: string
  author_name: string
  author_avatar: string | null
}

const CLIP_SELECT = `SELECT c.*, r.display_name AS author_name, r.avatar_url AS author_avatar
                       FROM event_video_clips c
                       JOIN residents r ON r.id = c.resident_id`

const toClipView = (r: ClipRow): EventClipView => ({
  id: r.id,
  eventId: r.event_id,
  residentId: r.resident_id,
  author: { id: r.resident_id, displayName: r.author_name, avatarUrl: r.author_avatar },
  durationMs: r.duration_ms,
  createdAt: r.created_at,
})

// created_at は ISO 8601（UTC, ミリ秒付き）で入れる（アプリがそのまま日時として読む）
export class D1EventClipRepository implements EventClipRepository {
  constructor(private readonly db: D1Database) {}

  async find(id: string): Promise<EventClipView | null> {
    const row = await this.db.prepare(`${CLIP_SELECT} WHERE c.id = ?`).bind(id).first<ClipRow>()
    return row ? toClipView(row) : null
  }

  async findRow(id: string): Promise<EventVideoClip | null> {
    const row = await this.db
      .prepare('SELECT * FROM event_video_clips WHERE id = ?')
      .bind(id)
      .first<Omit<ClipRow, 'author_name' | 'author_avatar'>>()
    return row
      ? {
          id: row.id,
          eventId: row.event_id,
          residentId: row.resident_id,
          r2Key: row.r2_key,
          durationMs: row.duration_ms,
          createdAt: row.created_at,
        }
      : null
  }

  async list(eventId: string): Promise<EventClipView[]> {
    const { results } = await this.db
      .prepare(`${CLIP_SELECT} WHERE c.event_id = ? ORDER BY c.created_at LIMIT 500`)
      .bind(eventId)
      .all<ClipRow>()
    return results.map(toClipView)
  }

  async countByResident(eventId: string, residentId: string): Promise<number> {
    const row = await this.db
      .prepare('SELECT COUNT(*) AS n FROM event_video_clips WHERE event_id = ? AND resident_id = ?')
      .bind(eventId, residentId)
      .first<{ n: number }>()
    return row?.n ?? 0
  }

  async create(clip: Omit<EventVideoClip, 'createdAt'>): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO event_video_clips (id, event_id, resident_id, r2_key, duration_ms, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(clip.id, clip.eventId, clip.residentId, clip.r2Key, clip.durationMs, new Date().toISOString())
      .run()
  }

  async delete(id: string): Promise<void> {
    await this.db.prepare('DELETE FROM event_video_clips WHERE id = ?').bind(id).run()
  }
}
