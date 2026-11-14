import type { AttributeCategory, AttributeCategoryRepository } from '../domain/attribute'

export function listAttributeCategories(
  repo: AttributeCategoryRepository
): Promise<AttributeCategory[]> {
  return repo.listAll()
}
