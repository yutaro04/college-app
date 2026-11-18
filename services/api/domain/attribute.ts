export interface AttributeCategory {
  id: string
  key: string
  label: string
  sortOrder: number
}

export interface Attribute {
  id: string
  categoryId: string
  value: string
  normalizedValue: string
  createdByResidentId: string | null
  createdAt: string
}

export interface AttributeCategoryRepository {
  listAll(): Promise<AttributeCategory[]>
}

// API が返す属性タグ。iOS の `ResidentAttribute` と同じ形
export interface AttributeView {
  id: string
  categoryKey: string
  value: string
}

export interface AttributeRepository {
  findCategoryByKey(key: string): Promise<AttributeCategory | null>
  // 使っている人が多い順
  search(categoryKey: string | null, normalizedQuery: string, limit: number): Promise<AttributeView[]>
  // (カテゴリ, 正規化した値) が同じタグがあれば再利用し、なければ作る
  findOrCreate(category: AttributeCategory, value: string, normalizedValue: string, residentId: string): Promise<AttributeView>
  listOf(residentId: string): Promise<AttributeView[]>
  attach(residentId: string, attributeId: string): Promise<void>
  detach(residentId: string, attributeId: string): Promise<void>
}

export const ATTRIBUTE_VALUE_MAX = 40
export const ATTRIBUTES_PER_RESIDENT_MAX = 100

// 表記ゆれの吸収（全角/半角・大文字/小文字・前後と連続する空白）。attributes.normalized_value に入れる値
export function normalizeAttributeValue(value: string): string {
  return value.normalize('NFKC').trim().replace(/\s+/g, ' ').toLowerCase()
}
