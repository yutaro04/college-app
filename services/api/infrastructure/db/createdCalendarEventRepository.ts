import type { CreatedCalendarEventRepository } from '../../domain/calendar'

export class D1CreatedCalendarEventRepository implements CreatedCalendarEventRepository {
  constructor(private readonly db: D1Database) {}

  async record(eventId: string, residentId: string): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO created_calendar_events (event_id, resident_id) VALUES (?, ?)
         ON CONFLICT (event_id) DO UPDATE SET resident_id = excluded.resident_id`
      )
      .bind(eventId, residentId)
      .run()
  }

  async listIds(residentId: string): Promise<string[]> {
    const { results } = await this.db
      .prepare('SELECT event_id FROM created_calendar_events WHERE resident_id = ? ORDER BY created_at DESC')
      .bind(residentId)
      .all<{ event_id: string }>()
    return results.map((r) => r.event_id)
  }
}
