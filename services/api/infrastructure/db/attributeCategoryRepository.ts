import type { AttributeCategory, AttributeCategoryRepository } from '../../domain/attribute'

interface AttributeCategoryRow {
  id: string
  key: string
  label: string
  sort_order: number
}

function toDomain(row: AttributeCategoryRow): AttributeCategory {
  return {
    id: row.id,
    key: row.key,
    label: row.label,
    sortOrder: row.sort_order,
  }
}

export class D1AttributeCategoryRepository implements AttributeCategoryRepository {
  constructor(private readonly db: D1Database) {}

  async listAll(): Promise<AttributeCategory[]> {
    const { results } = await this.db
      .prepare('SELECT id, key, label, sort_order FROM attribute_categories ORDER BY sort_order')
      .all<AttributeCategoryRow>()
    return results.map(toDomain)
  }
}
