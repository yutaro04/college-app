import {
  ATTRIBUTES_PER_RESIDENT_MAX,
  ATTRIBUTE_VALUE_MAX,
  normalizeAttributeValue,
  type AttributeRepository,
  type AttributeView,
} from '../domain/attribute'
import {
  DIRECTORY_LIMIT,
  type ResidentMatch,
  type ResidentProfile,
  type ResidentQuery,
  type ResidentRepository,
} from '../domain/resident'
import { UseCaseError } from './errors'

// 図鑑一覧。名前・タグの部分一致（q）、タグ（OR）、カテゴリで絞り込む
export async function searchResidents(repo: ResidentRepository, query: ResidentQuery): Promise<ResidentProfile[]> {
  return repo.search({ ...query, q: query.q.trim() }, DIRECTORY_LIMIT)
}

export async function getResident(repo: ResidentRepository, id: string): Promise<ResidentProfile> {
  const resident = await repo.findProfile(id)
  if (!resident) throw new UseCaseError(404, '居住者が見つかりません')
  return resident
}

// 共通点が多い人（自分と共有している属性の数が多い順）
export async function listMatches(repo: ResidentRepository, residentId: string): Promise<ResidentMatch[]> {
  const sharing = (await repo.findSharingAttributes(residentId))
    .sort((a, b) => b.attributeIds.length - a.attributeIds.length)
    .slice(0, DIRECTORY_LIMIT)
  const profiles = new Map((await repo.findProfiles(sharing.map((s) => s.residentId))).map((p) => [p.id, p]))
  return sharing.flatMap(({ residentId: id, attributeIds }) => {
    const resident = profiles.get(id)
    if (!resident) return []
    const shared = new Set(attributeIds)
    return [{ resident, sharedAttributes: resident.attributes.filter((a) => shared.has(a.id)) }]
  })
}

export async function searchAttributes(
  repo: AttributeRepository,
  categoryKey: string | null,
  q: string
): Promise<AttributeView[]> {
  return repo.search(categoryKey, normalizeAttributeValue(q), 100)
}

export async function addMyAttribute(
  repo: AttributeRepository,
  residentId: string,
  body: { categoryKey?: unknown; value?: unknown }
): Promise<AttributeView> {
  const key = typeof body.categoryKey === 'string' ? body.categoryKey : ''
  const value = typeof body.value === 'string' ? body.value.normalize('NFKC').trim().replace(/\s+/g, ' ') : ''
  const category = key ? await repo.findCategoryByKey(key) : null
  if (!category || !value) throw new UseCaseError(400, 'カテゴリと値を指定してください')
  if (value.length > ATTRIBUTE_VALUE_MAX) throw new UseCaseError(400, `タグは${ATTRIBUTE_VALUE_MAX}文字以内にしてください`)

  const mine = await repo.listOf(residentId)
  const attribute = await repo.findOrCreate(category, value, normalizeAttributeValue(value), residentId)
  if (mine.some((a) => a.id === attribute.id)) return attribute
  if (mine.length >= ATTRIBUTES_PER_RESIDENT_MAX) {
    throw new UseCaseError(400, `タグは${ATTRIBUTES_PER_RESIDENT_MAX}個までです`)
  }
  await repo.attach(residentId, attribute.id)
  return attribute
}
