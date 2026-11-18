import type { ResidentProfile, ResidentQuery, ResidentRepository } from '../../domain/resident'

interface ResidentRow {
  id: string
  display_name: string
  avatar_url: string | null
  bio: string | null
}

interface AttributeRow {
  resident_id: string
  id: string
  category_key: string
  value: string
}

// LIKE の特殊文字（% _ \）をそのまま探せるようにする。ESCAPE '\' と組で使う
function likeContains(value: string): string {
  return `%${value.replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`
}

export class D1ResidentRepository implements ResidentRepository {
  constructor(private readonly db: D1Database) {}

  async search(query: ResidentQuery, limit: number): Promise<ResidentProfile[]> {
    const where: string[] = []
    const values: (string | number)[] = []
    if (query.q) {
      // 名前か、持っているタグの部分一致
      where.push(`(r.display_name LIKE ? ESCAPE '\\' OR EXISTS (
        SELECT 1 FROM resident_attributes ra JOIN attributes a ON a.id = ra.attribute_id
         WHERE ra.resident_id = r.id AND a.normalized_value LIKE ? ESCAPE '\\'))`)
      values.push(likeContains(query.q), likeContains(query.q.normalize('NFKC').toLowerCase()))
    }
    if (query.attributeIds.length > 0) {
      where.push(`EXISTS (SELECT 1 FROM resident_attributes ra
        WHERE ra.resident_id = r.id AND ra.attribute_id IN (SELECT value FROM json_each(?)))`)
      values.push(JSON.stringify(query.attributeIds))
    }
    if (query.categoryKey) {
      where.push(`EXISTS (SELECT 1 FROM resident_attributes ra
        JOIN attributes a ON a.id = ra.attribute_id JOIN attribute_categories c ON c.id = a.category_id
        WHERE ra.resident_id = r.id AND c.key = ?)`)
      values.push(query.categoryKey)
    }
    const { results } = await this.db
      .prepare(
        `SELECT r.id FROM residents r ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
         ORDER BY r.display_name LIMIT ?`
      )
      .bind(...values, limit)
      .all<{ id: string }>()
    return this.findProfiles(results.map((r) => r.id))
  }

  async findSharingAttributes(residentId: string): Promise<{ residentId: string; attributeIds: string[] }[]> {
    const { results } = await this.db
      .prepare(
        `SELECT theirs.resident_id, theirs.attribute_id
           FROM resident_attributes mine
           JOIN resident_attributes theirs ON theirs.attribute_id = mine.attribute_id
          WHERE mine.resident_id = ? AND theirs.resident_id != mine.resident_id`
      )
      .bind(residentId)
      .all<{ resident_id: string; attribute_id: string }>()
    const grouped = new Map<string, string[]>()
    for (const r of results) grouped.set(r.resident_id, [...(grouped.get(r.resident_id) ?? []), r.attribute_id])
    return [...grouped].map(([id, attributeIds]) => ({ residentId: id, attributeIds }))
  }

  // 名前順。存在しない id は飛ばす
  async findProfiles(ids: string[]): Promise<ResidentProfile[]> {
    if (ids.length === 0) return []
    const idsJson = JSON.stringify(ids)
    const [residents, attributes] = await this.db.batch([
      this.db
        .prepare(
          `SELECT id, display_name, avatar_url, bio FROM residents
            WHERE id IN (SELECT value FROM json_each(?)) ORDER BY display_name`
        )
        .bind(idsJson),
      this.db
        .prepare(
          `SELECT ra.resident_id, a.id, c.key AS category_key, a.value
             FROM resident_attributes ra
             JOIN attributes a ON a.id = ra.attribute_id
             JOIN attribute_categories c ON c.id = a.category_id
            WHERE ra.resident_id IN (SELECT value FROM json_each(?))
            ORDER BY c.sort_order, a.value`
        )
        .bind(idsJson),
    ])
    const byResident = new Map<string, ResidentProfile['attributes']>()
    for (const a of attributes.results as AttributeRow[]) {
      const list = byResident.get(a.resident_id) ?? []
      list.push({ id: a.id, categoryKey: a.category_key, value: a.value })
      byResident.set(a.resident_id, list)
    }
    return (residents.results as ResidentRow[]).map((row) => ({
      id: row.id,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      bio: row.bio,
      attributes: byResident.get(row.id) ?? [],
    }))
  }

  async findProfile(id: string): Promise<ResidentProfile | null> {
    return (await this.findProfiles([id]))[0] ?? null
  }

  async updateProfile(id: string, patch: { displayName?: string; bio?: string | null }): Promise<void> {
    const sets: string[] = []
    const values: (string | null)[] = []
    if (patch.displayName !== undefined) {
      sets.push('display_name = ?')
      values.push(patch.displayName)
    }
    if (patch.bio !== undefined) {
      sets.push('bio = ?')
      values.push(patch.bio)
    }
    if (sets.length === 0) return
    await this.db
      .prepare(`UPDATE residents SET ${sets.join(', ')}, updated_at = datetime('now') WHERE id = ?`)
      .bind(...values, id)
      .run()
  }
}
