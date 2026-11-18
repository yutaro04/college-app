import type { DirectoryEntry, InviteGroup, InviteGroupRepository } from '../../domain/hima'

interface GroupRow {
  id: string
  name: string
  emails: string
}

function toGroup(row: GroupRow): InviteGroup {
  return { id: row.id, name: row.name, emails: JSON.parse(row.emails) as string[] }
}

export class D1InviteGroupRepository implements InviteGroupRepository {
  constructor(private readonly db: D1Database) {}

  async listByOwner(ownerId: string): Promise<InviteGroup[]> {
    const { results } = await this.db
      .prepare('SELECT id, name, emails FROM invite_groups WHERE owner_id = ? ORDER BY created_at, id')
      .bind(ownerId)
      .all<GroupRow>()
    return results.map(toGroup)
  }

  async create(ownerId: string, name: string, emails: string[]): Promise<InviteGroup> {
    const id = crypto.randomUUID()
    await this.db
      .prepare('INSERT INTO invite_groups (id, owner_id, name, emails) VALUES (?, ?, ?, ?)')
      .bind(id, ownerId, name, JSON.stringify(emails))
      .run()
    return { id, name, emails }
  }

  async delete(ownerId: string, id: string): Promise<boolean> {
    const result = await this.db
      .prepare('DELETE FROM invite_groups WHERE id = ? AND owner_id = ?')
      .bind(id, ownerId)
      .run()
    return result.meta.changes > 0
  }

  async directory(): Promise<DirectoryEntry[]> {
    const { results } = await this.db
      .prepare(
        `SELECT r.id, r.display_name, u.email
           FROM residents r JOIN users u ON u.id = r.user_id
          ORDER BY r.display_name`
      )
      .all<{ id: string; display_name: string; email: string }>()
    return results.map((r) => ({ id: r.id, displayName: r.display_name, email: r.email }))
  }
}
