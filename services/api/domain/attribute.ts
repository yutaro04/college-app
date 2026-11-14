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
