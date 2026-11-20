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
  deleted_at: string | null
}

const UPSERT_SQL = `INSERT INTO calendar_events
  (event_id, start_iso, end_iso, calendar_name, title, description, location,
   date_key, start_time, end_time, display_date, is_all_day, is_recurring, color)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT (event_id, start_iso) DO UPDATE SET
    end_iso = excluded.end_iso, calendar_name = excluded.calendar_name, title = excluded.title,
    description = excluded.description, location = excluded.location, date_key = excluded.date_key,
    start_time = excluded.start_time, end_time = excluded.end_time, display_date = excluded.display_date,
    is_all_day = excluded.is_all_day, is_recurring = excluded.is_recurring, color = excluded.color,
    deleted_at = NULL`

const META_SQL = `INSERT INTO calendar_meta (key, value, updated_at) VALUES (?, ?, datetime('now'))
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`

export class D1CalendarCacheRepository implements CalendarCacheRepository {
  constructor(private readonly db: D1Database) {}

  async syncRange(from: string, to: string, events: CalendarEvent[], syncedAt: string): Promise<void> {
    // D1 は書いた行数（インデックスの更新も含む）で制限されるので、いまの行と突き合わせて差分だけを書く:
    //   - 消えた予定 → deleted_at を入れる（論理削除。インデックス列は変えないので 1 行で済む）
    //   - 新しい予定 → 追加。消した予定が戻ってきたとき・内容が変わったときは上書き（deleted_at も戻す）
    //   - 変わらない予定 → 何もしない
    // GAS は範囲に重なる予定を返すので、範囲の少し前に始まる予定も来る。比べる行はそこまで広げて読む
    const lower = events.reduce((min, e) => (e.startISO < min ? e.startISO : min), from)
    const { results } = await this.db
      .prepare('SELECT * FROM calendar_events WHERE start_iso >= ? AND start_iso < ?')
      .bind(lower, to)
      .all<Row>()
    const current = new Map(results.map((r) => [rowKey(r.event_id, r.start_iso), r]))
    const incoming = new Set(events.map((e) => rowKey(e.id, e.startISO)))

    const statements: D1PreparedStatement[] = []
    for (const [key, r] of current) {
      // 範囲より前に始まった予定は、GAS が返さなくても消えたとは限らないので触らない
      if (r.deleted_at === null && r.start_iso >= from && !incoming.has(key)) {
        statements.push(
          this.db
            .prepare('UPDATE calendar_events SET deleted_at = ? WHERE event_id = ? AND start_iso = ?')
            .bind(syncedAt, r.event_id, r.start_iso)
        )
      }
    }
    for (const e of events) {
      const r = current.get(rowKey(e.id, e.startISO))
      if (!r || r.deleted_at !== null || fingerprint(toEvent(r)) !== fingerprint(e)) statements.push(this.bindEvent(e))
    }
    // 何も変わっていなければ 1 行も書かない（版も進めない。アプリのキャッシュもそのまま使われる）
    if (statements.length === 0 && (await this.version()) !== null) return
    // batch は 1 トランザクションで走るので、途中で失敗しても一覧が中途半端にならない
    await this.db.batch([...statements, this.db.prepare(META_SQL).bind('version', syncedAt)])
  }

  async upsert(event: CalendarEvent, changedAt: string): Promise<void> {
    await this.db.batch([this.bindEvent(event), this.db.prepare(META_SQL).bind('version', changedAt)])
  }

  async list(from: string, to: string): Promise<CalendarEvent[]> {
    // 読んだ行数も数えられるので、頼まれた期間だけを start_iso のインデックスで読む
    const { results } = await this.db
      .prepare(
        `SELECT * FROM calendar_events
          WHERE start_iso >= ? AND start_iso < ? AND deleted_at IS NULL
          ORDER BY start_iso, event_id`
      )
      .bind(from, to)
      .all<Row>()
    return results.map(toEvent)
  }

  async version(): Promise<string | null> {
    return this.meta('version')
  }

  async savePostConfig(config: PostConfig): Promise<void> {
    const value = JSON.stringify(config)
    if ((await this.meta('post_config')) === value) return // 変わっていなければ書かない
    await this.db.prepare(META_SQL).bind('post_config', value).run()
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

const rowKey = (eventId: string, startISO: string) => `${eventId}\u0000${startISO}`

// 書き直しが要るかの判定用。列の値をすべて並べる
function fingerprint(e: CalendarEvent): string {
  return JSON.stringify([
    e.endISO, e.calendarName, e.title, e.description, e.location, e.dateKey,
    e.startTime, e.endTime, e.displayDate, e.isAllDay, e.isRecurring, e.color,
  ])
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
