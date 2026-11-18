import type { AttributeCategory, AttributeRepository, AttributeView } from '../../domain/attribute'

interface ViewRow {
  id: string
  category_key: string
  value: string
}

const toView = (r: ViewRow): AttributeView => ({ id: r.id, categoryKey: r.category_key, value: r.value })

export class D1AttributeRepository implements AttributeRepository {
  constructor(private readonly db: D1Database) {}

  async findCategoryByKey(key: string): Promise<AttributeCategory | null> {
    const row = await this.db
      .prepare('SELECT id, key, label, sort_order FROM attribute_categories WHERE key = ?')
      .bind(key)
      .first<{ id: string; key: string; label: string; sort_order: number }>()
    return row ? { id: row.id, key: row.key, label: row.label, sortOrder: row.sort_order } : null
  }

  async search(categoryKey: string | null, normalizedQuery: string, limit: number): Promise<AttributeView[]> {
    const pattern = `%${normalizedQuery.replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`
    const { results } = await this.db
      .prepare(
        `SELECT a.id, c.key AS category_key, a.value
           FROM attributes a
           JOIN attribute_categories c ON c.id = a.category_id
           LEFT JOIN resident_attributes ra ON ra.attribute_id = a.id
          WHERE (? IS NULL OR c.key = ?) AND a.normalized_value LIKE ? ESCAPE '\\'
          GROUP BY a.id
          ORDER BY COUNT(ra.resident_id) DESC, a.value
          LIMIT ?`
      )
      .bind(categoryKey, categoryKey, pattern, limit)
      .all<ViewRow>()
    return results.map(toView)
  }

  async findOrCreate(
    category: AttributeCategory,
    value: string,
    normalizedValue: string,
    residentId: string
  ): Promise<AttributeView> {
    // 同時に同じタグが作られても UNIQUE (category_id, normalized_value) で 1 つに収まる
    await this.db
      .prepare(
        `INSERT INTO attributes (id, category_id, value, normalized_value, created_by_resident_id)
         VALUES (?, ?, ?, ?, ?) ON CONFLICT (category_id, normalized_value) DO NOTHING`
      )
      .bind(crypto.randomUUID(), category.id, value, normalizedValue, residentId)
      .run()
    const row = await this.db
      .prepare('SELECT id, value FROM attributes WHERE category_id = ? AND normalized_value = ?')
      .bind(category.id, normalizedValue)
      .first<{ id: string; value: string }>()
    return { id: row!.id, categoryKey: category.key, value: row!.value }
  }

  async listOf(residentId: string): Promise<AttributeView[]> {
    const { results } = await this.db
      .prepare(
        `SELECT a.id, c.key AS category_key, a.value
           FROM resident_attributes ra
           JOIN attributes a ON a.id = ra.attribute_id
           JOIN attribute_categories c ON c.id = a.category_id
          WHERE ra.resident_id = ?
          ORDER BY c.sort_order, a.value`
      )
      .bind(residentId)
      .all<ViewRow>()
    return results.map(toView)
  }

  async attach(residentId: string, attributeId: string): Promise<void> {
    await this.db
      .prepare('INSERT INTO resident_attributes (resident_id, attribute_id) VALUES (?, ?) ON CONFLICT DO NOTHING')
      .bind(residentId, attributeId)
      .run()
  }

  async detach(residentId: string, attributeId: string): Promise<void> {
    await this.db
      .prepare('DELETE FROM resident_attributes WHERE resident_id = ? AND attribute_id = ?')
      .bind(residentId, attributeId)
      .run()
  }
}
