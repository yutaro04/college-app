import type { HimaInvite, HimaRepository, HimaStatus } from '../../domain/hima'

interface StatusRow {
  id: string
  resident_id: string
  display_name: string
  avatar_url: string | null
  message: string
  expires_at: string
  created_at: string
}

interface InviteRow {
  id: string
  inviter_id: string
  display_name: string
  avatar_url: string | null
  message: string
  created_at: string
}

function toStatus(row: StatusRow): HimaStatus {
  return {
    id: row.id,
    resident: { id: row.resident_id, displayName: row.display_name, avatarUrl: row.avatar_url },
    message: row.message,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
  }
}

function toInvite(row: InviteRow): HimaInvite {
  return {
    id: row.id,
    inviter: { id: row.inviter_id, displayName: row.display_name, avatarUrl: row.avatar_url },
    message: row.message,
    createdAt: row.created_at,
  }
}

const STATUS_COLUMNS = `s.id, s.resident_id, r.display_name, r.avatar_url, s.message, s.expires_at, s.created_at
  FROM hima_statuses s JOIN residents r ON r.id = s.resident_id`

export class D1HimaRepository implements HimaRepository {
  constructor(private readonly db: D1Database) {}

  async listActive(now: string): Promise<HimaStatus[]> {
    const { results } = await this.db
      .prepare(`SELECT ${STATUS_COLUMNS} WHERE s.expires_at > ? ORDER BY s.created_at DESC`)
      .bind(now)
      .all<StatusRow>()
    return results.map(toStatus)
  }

  async replace(residentId: string, message: string, expiresAt: string, now: string): Promise<HimaStatus> {
    const id = crypto.randomUUID()
    await this.db.batch([
      this.db.prepare('DELETE FROM hima_statuses WHERE resident_id = ?').bind(residentId),
      this.db
        .prepare('INSERT INTO hima_statuses (id, resident_id, message, expires_at, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(id, residentId, message, expiresAt, now),
    ])
    const row = await this.db.prepare(`SELECT ${STATUS_COLUMNS} WHERE s.id = ?`).bind(id).first<StatusRow>()
    if (!row) throw new Error('failed to create hima status')
    return toStatus(row)
  }

  async clear(residentId: string): Promise<void> {
    await this.db.prepare('DELETE FROM hima_statuses WHERE resident_id = ?').bind(residentId).run()
  }

  async findActive(statusId: string, now: string): Promise<{ residentId: string } | null> {
    const row = await this.db
      .prepare('SELECT resident_id FROM hima_statuses WHERE id = ? AND expires_at > ?')
      .bind(statusId, now)
      .first<{ resident_id: string }>()
    return row ? { residentId: row.resident_id } : null
  }

  async addInvite(statusId: string, inviterId: string, message: string, now: string): Promise<HimaInvite> {
    const id = crypto.randomUUID()
    await this.db
      .prepare('INSERT INTO hima_invites (id, status_id, inviter_id, message, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, statusId, inviterId, message, now)
      .run()
    const row = await this.db
      .prepare(
        `SELECT i.id, i.inviter_id, r.display_name, r.avatar_url, i.message, i.created_at
           FROM hima_invites i JOIN residents r ON r.id = i.inviter_id WHERE i.id = ?`
      )
      .bind(id)
      .first<InviteRow>()
    if (!row) throw new Error('failed to create hima invite')
    return toInvite(row)
  }

  async listInvitesFor(residentId: string, limit: number): Promise<HimaInvite[]> {
    const { results } = await this.db
      .prepare(
        `SELECT i.id, i.inviter_id, r.display_name, r.avatar_url, i.message, i.created_at
           FROM hima_invites i
           JOIN hima_statuses s ON s.id = i.status_id
           JOIN residents r ON r.id = i.inviter_id
          WHERE s.resident_id = ?
          ORDER BY i.created_at DESC
          LIMIT ?`
      )
      .bind(residentId, limit)
      .all<InviteRow>()
    return results.map(toInvite)
  }
}
