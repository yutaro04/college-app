import type { AuthContext, AuthRepository, GoogleIdentity } from '../../domain/auth'
import type { User } from '../../domain/user'

interface UserRow {
  id: string
  email: string
  google_sub: string
  created_at: string
  resident_id: string
}

function toUser(row: UserRow): User {
  return { id: row.id, email: row.email, googleSub: row.google_sub, createdAt: row.created_at }
}

export class D1AuthRepository implements AuthRepository {
  constructor(private readonly db: D1Database) {}

  async findOrCreateByGoogle(identity: GoogleIdentity): Promise<{ user: User; residentId: string }> {
    const existing = await this.findByGoogleSub(identity.sub)
    if (existing) {
      if (existing.email !== identity.email) {
        await this.db.prepare('UPDATE users SET email = ? WHERE id = ?').bind(identity.email, existing.id).run()
      }
      return { user: { ...toUser(existing), email: identity.email }, residentId: existing.resident_id }
    }

    // 初回ログイン: users と residents（図鑑のプロフィール）を同時に作る。表示名・アイコンは Google のものを初期値にする
    const userId = crypto.randomUUID()
    const residentId = crypto.randomUUID()
    const displayName = identity.name ?? identity.email.split('@')[0]
    await this.db.batch([
      this.db
        .prepare('INSERT INTO users (id, email, google_sub) VALUES (?, ?, ?)')
        .bind(userId, identity.email, identity.sub),
      this.db
        .prepare('INSERT INTO residents (id, user_id, display_name, avatar_url) VALUES (?, ?, ?, ?)')
        .bind(residentId, userId, displayName, identity.picture),
    ])
    const created = await this.findByGoogleSub(identity.sub)
    if (!created) throw new Error('failed to create user')
    return { user: toUser(created), residentId: created.resident_id }
  }

  async createSession(tokenHash: string, userId: string, expiresAt: string | null): Promise<void> {
    await this.db
      .prepare('INSERT INTO sessions (id, user_id, expires_at) VALUES (?, ?, ?)')
      .bind(tokenHash, userId, expiresAt)
      .run()
  }

  async findSession(tokenHash: string): Promise<AuthContext | null> {
    const row = await this.db
      .prepare(
        `SELECT s.user_id, r.id AS resident_id, u.email
           FROM sessions s
           JOIN users u ON u.id = s.user_id
           JOIN residents r ON r.user_id = s.user_id
          WHERE s.id = ? AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))`
      )
      .bind(tokenHash)
      .first<{ user_id: string; resident_id: string; email: string }>()
    return row ? { userId: row.user_id, residentId: row.resident_id, email: row.email } : null
  }

  async deleteSession(tokenHash: string): Promise<void> {
    await this.db.prepare('DELETE FROM sessions WHERE id = ?').bind(tokenHash).run()
  }

  private findByGoogleSub(sub: string): Promise<UserRow | null> {
    return this.db
      .prepare(
        `SELECT u.id, u.email, u.google_sub, u.created_at, r.id AS resident_id
           FROM users u JOIN residents r ON r.user_id = u.id
          WHERE u.google_sub = ?`
      )
      .bind(sub)
      .first<UserRow>()
  }
}
