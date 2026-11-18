import type { PenPalLetter, PenPalRepository, PenPalThread } from '../../domain/social'

// 匿名文通の D1 リポジトリ。
// 匿名性を守るため、相手の resident_id は SELECT しない（自分視点の alias・from_me は SQL の中で計算する）

interface ThreadRow {
  id: string
  my_alias: string
  partner_alias: string
  created_at: string
  closed_at: string | null
  last_id: string | null
  last_from_me: number | null
  last_body: string | null
  last_created_at: string | null
  unread_count: number
}

interface LetterRow {
  id: string
  from_me: number
  body: string
  created_at: string
}

// ?1 は閲覧者（自分）の resident id
const THREAD_VIEW = `
  SELECT t.id,
         CASE WHEN t.starter_resident_id = ?1 THEN t.starter_alias ELSE t.partner_alias END AS my_alias,
         CASE WHEN t.starter_resident_id = ?1 THEN t.partner_alias ELSE t.starter_alias END AS partner_alias,
         t.created_at, t.closed_at,
         l.id AS last_id, (l.sender_resident_id = ?1) AS last_from_me, l.body AS last_body, l.created_at AS last_created_at,
         (SELECT COUNT(*) FROM pen_pal_letters u
           WHERE u.thread_id = t.id AND u.sender_resident_id != ?1 AND u.read_at IS NULL) AS unread_count
    FROM pen_pal_threads t
    LEFT JOIN pen_pal_letters l ON l.id = (
      SELECT x.id FROM pen_pal_letters x WHERE x.thread_id = t.id ORDER BY x.created_at DESC, x.rowid DESC LIMIT 1
    )
   WHERE (t.starter_resident_id = ?1 OR t.partner_resident_id = ?1)`

function toThread(row: ThreadRow): PenPalThread {
  return {
    id: row.id,
    myAlias: row.my_alias,
    partnerAlias: row.partner_alias,
    createdAt: row.created_at,
    closedAt: row.closed_at,
    lastLetter:
      row.last_id && row.last_body !== null && row.last_created_at
        ? { id: row.last_id, fromMe: row.last_from_me === 1, body: row.last_body, createdAt: row.last_created_at }
        : null,
    unreadCount: row.unread_count,
  }
}

function toLetter(row: LetterRow): PenPalLetter {
  return { id: row.id, fromMe: row.from_me === 1, body: row.body, createdAt: row.created_at }
}

export class D1PenPalRepository implements PenPalRepository {
  constructor(private readonly db: D1Database) {}

  async listThreads(residentId: string): Promise<PenPalThread[]> {
    const { results } = await this.db
      .prepare(`${THREAD_VIEW} ORDER BY COALESCE(l.created_at, t.created_at) DESC`)
      .bind(residentId)
      .all<ThreadRow>()
    return results.map(toThread)
  }

  async findThread(residentId: string, threadId: string): Promise<PenPalThread | null> {
    const row = await this.db.prepare(`${THREAD_VIEW} AND t.id = ?2`).bind(residentId, threadId).first<ThreadRow>()
    return row ? toThread(row) : null
  }

  async pickPartner(residentId: string): Promise<string | null> {
    // 除外: 自分 / いま文通中の相手 / 通報が絡んだスレッドの相手（どちらが通報したかによらない）
    const row = await this.db
      .prepare(
        `SELECT r.id FROM residents r
          WHERE r.id != ?1
            AND NOT EXISTS (
              SELECT 1 FROM pen_pal_threads t
               WHERE ((t.starter_resident_id = ?1 AND t.partner_resident_id = r.id)
                   OR (t.partner_resident_id = ?1 AND t.starter_resident_id = r.id))
                 AND (t.closed_at IS NULL OR EXISTS (SELECT 1 FROM pen_pal_reports p WHERE p.thread_id = t.id))
            )
          ORDER BY RANDOM()
          LIMIT 1`
      )
      .bind(residentId)
      .first<{ id: string }>()
    return row?.id ?? null
  }

  async start(
    starterId: string,
    partnerId: string,
    aliases: { starter: string; partner: string },
    body: string,
    now: string
  ): Promise<string> {
    const threadId = crypto.randomUUID()
    await this.db.batch([
      this.db
        .prepare(
          `INSERT INTO pen_pal_threads (id, starter_resident_id, partner_resident_id, starter_alias, partner_alias, created_at)
           VALUES (?, ?, ?, ?, ?, ?)`
        )
        .bind(threadId, starterId, partnerId, aliases.starter, aliases.partner, now),
      this.db
        .prepare('INSERT INTO pen_pal_letters (id, thread_id, sender_resident_id, body, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(crypto.randomUUID(), threadId, starterId, body, now),
    ])
    return threadId
  }

  async readLetters(residentId: string, threadId: string, now: string): Promise<PenPalLetter[]> {
    const [, letters] = await this.db.batch([
      this.db
        .prepare(
          'UPDATE pen_pal_letters SET read_at = ? WHERE thread_id = ? AND sender_resident_id != ? AND read_at IS NULL'
        )
        .bind(now, threadId, residentId),
      this.db
        .prepare(
          `SELECT id, (sender_resident_id = ?) AS from_me, body, created_at
             FROM pen_pal_letters WHERE thread_id = ? ORDER BY created_at, rowid`
        )
        .bind(residentId, threadId),
    ])
    return (letters.results as LetterRow[]).map(toLetter)
  }

  async addLetter(residentId: string, threadId: string, body: string, now: string): Promise<PenPalLetter> {
    const id = crypto.randomUUID()
    await this.db
      .prepare('INSERT INTO pen_pal_letters (id, thread_id, sender_resident_id, body, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, threadId, residentId, body, now)
      .run()
    return { id, fromMe: true, body, createdAt: now }
  }

  async close(threadId: string, now: string): Promise<void> {
    await this.db
      .prepare('UPDATE pen_pal_threads SET closed_at = ? WHERE id = ? AND closed_at IS NULL')
      .bind(now, threadId)
      .run()
  }

  async report(residentId: string, threadId: string, reason: string | null, now: string): Promise<void> {
    await this.db
      .prepare('INSERT INTO pen_pal_reports (id, thread_id, reporter_resident_id, reason, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(crypto.randomUUID(), threadId, residentId, reason, now)
      .run()
  }
}
