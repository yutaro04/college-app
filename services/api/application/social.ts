import {
  RECOMMENDATION_GENRES,
  SOCIAL_LIMITS as L,
  type FreeSlot,
  type FreeSlotRepository,
  type HimaGathering,
  type HimaGatheringRepository,
  type InviteWish,
  type InviteWishRepository,
  type LikeCandidate,
  type LikeRepository,
  type Recommendation,
  type RecommendationGenre,
  type RecommendationRepository,
} from '../domain/social'
import { UseCaseError } from './errors'

// 交流機能（匿名文通以外）のユースケース。文通は penPals.ts

// MARK: - 入力の整形

// 前後の空白を除いた文字列。空なら null。上限を超えたら 400
export function optionalText(raw: unknown, max: number, label: string): string | null {
  if (raw === undefined || raw === null) return null
  if (typeof raw !== 'string') throw new UseCaseError(400, `${label}が不正です`)
  const text = raw.trim()
  if (text.length > max) throw new UseCaseError(400, `${label}は${max}文字以内にしてください`)
  return text || null
}

export function requiredText(raw: unknown, max: number, label: string, emptyMessage: string): string {
  const text = optionalText(raw, max, label)
  if (!text) throw new UseCaseError(400, emptyMessage)
  return text
}

// ISO 8601 の日時を UTC の toISOString() 形式にそろえる（DB では文字列比較するため）
function isoDate(raw: unknown): string | null {
  if (typeof raw !== 'string' || !raw) return null
  const d = new Date(raw)
  return isNaN(d.getTime()) ? null : d.toISOString()
}

function isGenre(raw: unknown): raw is RecommendationGenre {
  return typeof raw === 'string' && (RECOMMENDATION_GENRES as readonly string[]).includes(raw)
}

// スキーム無しの URL は https:// を補う。http(s) 以外（javascript: など）は受け付けない
function normalizeUrl(raw: unknown): string | null {
  const text = optionalText(raw, L.url, 'URL')
  if (!text) return null
  if (/^https?:\/\//i.test(text)) return text
  if (/^[a-z][a-z0-9+.-]*:/i.test(text) && !/^[^:/]+:\d+/.test(text)) {
    throw new UseCaseError(400, 'URL は http:// か https:// で始まるものにしてください')
  }
  return `https://${text}`
}

const DAY_MS = 24 * 60 * 60 * 1000

// MARK: - おすすめの店

export function listRecommendations(
  repo: RecommendationRepository,
  query: { genre?: string; q?: string }
): Promise<Recommendation[]> {
  if (query.genre !== undefined && query.genre !== '' && !isGenre(query.genre)) {
    throw new UseCaseError(400, 'ジャンルが不正です')
  }
  const genre = isGenre(query.genre) ? query.genre : undefined
  const q = optionalText(query.q, L.query, '検索語') ?? undefined
  return repo.list({ genre, q }, 200)
}

export function addRecommendation(
  repo: RecommendationRepository,
  residentId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<Recommendation> {
  const name = requiredText(body.name, L.recommendationName, '店名', '店名とジャンルを入力してください')
  if (!isGenre(body.genre)) throw new UseCaseError(400, '店名とジャンルを入力してください')
  return repo.create(
    residentId,
    {
      name,
      genre: body.genre,
      area: optionalText(body.area, L.recommendationArea, 'エリア'),
      comment: optionalText(body.comment, L.recommendationComment, 'コメント'),
      url: normalizeUrl(body.url),
    },
    now.toISOString()
  )
}

export async function deleteRecommendation(repo: RecommendationRepository, residentId: string, id: string) {
  if (!(await repo.delete(residentId, id))) throw new UseCaseError(404, '見つかりません')
}

// MARK: - 気になる

// まだ振り分けていない人を、共通する属性の多い順に返す（同数なら名前順）
export async function discoverCandidates(repo: LikeRepository, residentId: string, limit = 50): Promise<LikeCandidate[]> {
  const [mine, others] = await Promise.all([repo.myAttributeIds(residentId), repo.listUndecided(residentId)])
  const mineSet = new Set(mine)
  return others
    .map((resident) => ({ resident, sharedAttributes: resident.attributes.filter((a) => mineSet.has(a.id)) }))
    .sort(
      (a, b) =>
        b.sharedAttributes.length - a.sharedAttributes.length ||
        a.resident.displayName.localeCompare(b.resident.displayName, 'ja')
    )
    .slice(0, limit)
}

// 気になる / スキップを記録する。お互いに like ならマッチ（matched: true）
export async function putLike(
  repo: LikeRepository,
  residentId: string,
  targetId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<{ matched: boolean }> {
  if (targetId === residentId || !(await repo.residentExists(targetId))) {
    throw new UseCaseError(400, '相手が見つかりません')
  }
  const kind = body.kind
  if (kind !== 'like' && kind !== 'pass') throw new UseCaseError(400, 'kind は like か pass です')
  // pass のときの topic は意味が無いので捨てる
  const topic = kind === 'like' ? optionalText(body.topic, L.likeTopic, 'トピック') : null
  const matched = await repo.upsert(residentId, targetId, kind, topic, now.toISOString())
  return { matched }
}

// MARK: - 〇〇あったら誘って

export function listInviteWishes(
  repo: InviteWishRepository,
  query: { residentId?: string; q?: string }
): Promise<InviteWish[]> {
  return repo.list(
    { residentId: query.residentId || undefined, q: optionalText(query.q, L.query, '検索語') ?? undefined },
    200
  )
}

export function addInviteWish(
  repo: InviteWishRepository,
  residentId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<InviteWish> {
  const title = requiredText(body.title, L.wishTitle, '内容', '内容を入力してください')
  return repo.create(residentId, title, optionalText(body.note, L.wishNote, 'メモ'), now.toISOString())
}

export async function deleteInviteWish(repo: InviteWishRepository, residentId: string, id: string) {
  if (!(await repo.delete(residentId, id))) throw new UseCaseError(404, '見つかりません')
}

export async function inviteForWish(
  repo: InviteWishRepository,
  inviterId: string,
  wishId: string,
  body: Record<string, unknown>,
  now = new Date()
) {
  const owner = await repo.findOwner(wishId)
  if (!owner) throw new UseCaseError(404, '見つかりません')
  if (owner === inviterId) throw new UseCaseError(400, '自分の「誘って」には誘えません')
  // メッセージ省略時はモック（iOS）と同じ定型文
  const message = optionalText(body.message, L.invitationMessage, 'メッセージ') ?? '誘いたいです！'
  return repo.addInvitation(wishId, inviterId, message, now.toISOString())
}

// MARK: - 空き時間

// 期間の指定（from/to）。両方省略なら今から 7 日間
function range(query: { from?: string; to?: string }, now: Date): { from: string; to: string; explicit: boolean } {
  if (!query.from && !query.to) {
    return { from: now.toISOString(), to: new Date(now.getTime() + 7 * DAY_MS).toISOString(), explicit: false }
  }
  const from = isoDate(query.from)
  const to = isoDate(query.to)
  if (!from || !to || to <= from) throw new UseCaseError(400, '期間が不正です')
  return { from, to, explicit: true }
}

export function listResidentFreeSlots(
  repo: FreeSlotRepository,
  residentId: string,
  query: { from?: string; to?: string },
  now = new Date()
): Promise<FreeSlot[]> {
  const { from, to } = range(query, now)
  return repo.listByResident(residentId, from, to)
}

// 期間を指定すると、その時間帯をまるごと空けている人だけ。省略時は全員の 7 日分（自分は除く）
export function listEveryonesFreeSlots(
  repo: FreeSlotRepository,
  residentId: string,
  query: { from?: string; to?: string },
  now = new Date()
): Promise<FreeSlot[]> {
  const { from, to, explicit } = range(query, now)
  return explicit ? repo.listCovering(residentId, from, to) : repo.listOverlapping(residentId, from, to)
}

export function addFreeSlot(
  repo: FreeSlotRepository,
  residentId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<FreeSlot> {
  const startsAt = isoDate(body.startsAt)
  const endsAt = isoDate(body.endsAt)
  if (!startsAt || !endsAt || endsAt <= startsAt) throw new UseCaseError(400, '終了は開始より後にしてください')
  if (endsAt <= now.toISOString()) throw new UseCaseError(400, '過去の時間は登録できません')
  if (new Date(endsAt).getTime() - new Date(startsAt).getTime() > 7 * DAY_MS) {
    throw new UseCaseError(400, '空き時間は7日以内にしてください')
  }
  return repo.create(residentId, startsAt, endsAt, optionalText(body.note, L.slotNote, 'メモ'), now.toISOString())
}

export async function deleteFreeSlot(repo: FreeSlotRepository, residentId: string, id: string) {
  if (!(await repo.delete(residentId, id))) throw new UseCaseError(404, '見つかりません')
}

// MARK: - ひま募集

export function createHimaGathering(
  repo: HimaGatheringRepository,
  hostId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<HimaGathering> {
  const title = requiredText(body.title, L.gatheringTitle, 'タイトル', 'タイトルと時間を正しく入力してください')
  const startsAt = isoDate(body.startsAt)
  const endsAt = isoDate(body.endsAt)
  if (!startsAt || !endsAt || endsAt <= startsAt) throw new UseCaseError(400, 'タイトルと時間を正しく入力してください')
  if (endsAt <= now.toISOString()) throw new UseCaseError(400, 'もう終わっている時間です')
  if (new Date(endsAt).getTime() - new Date(startsAt).getTime() > DAY_MS) {
    throw new UseCaseError(400, '募集の時間は24時間以内にしてください')
  }
  let capacity: number | null = null
  if (body.capacity !== undefined && body.capacity !== null) {
    if (
      typeof body.capacity !== 'number' ||
      !Number.isInteger(body.capacity) ||
      body.capacity < 1 ||
      body.capacity > L.gatheringCapacity
    ) {
      throw new UseCaseError(400, `定員は1〜${L.gatheringCapacity}人にしてください`)
    }
    capacity = body.capacity
  }
  return repo.create(
    hostId,
    {
      title,
      location: optionalText(body.location, L.gatheringLocation, '場所'),
      startsAt,
      endsAt,
      capacity,
      note: optionalText(body.note, L.gatheringNote, 'メモ'),
    },
    now.toISOString()
  )
}

export async function cancelHimaGathering(
  repo: HimaGatheringRepository,
  residentId: string,
  id: string,
  now = new Date()
) {
  const state = await repo.findState(id)
  if (!state || state.cancelled) throw new UseCaseError(404, '見つかりません')
  if (state.hostId !== residentId) throw new UseCaseError(403, '主催者だけが取り消せます')
  await repo.cancel(id, now.toISOString())
}

// 参加 / 参加取り消し。結果の募集（参加者つき）を返す
export async function setHimaGatheringJoined(
  repo: HimaGatheringRepository,
  residentId: string,
  id: string,
  joined: boolean,
  now = new Date()
): Promise<HimaGathering> {
  const state = await repo.findState(id)
  if (!state || state.cancelled) throw new UseCaseError(404, '見つかりません')
  if (joined) {
    if (state.endsAt <= now.toISOString()) throw new UseCaseError(404, 'この募集はもう終わっています')
    if (state.hostId === residentId) throw new UseCaseError(400, '主催者は参加者に数えません')
    if (!(await repo.join(id, residentId, now.toISOString()))) throw new UseCaseError(409, '定員に達しています')
  } else {
    await repo.leave(id, residentId)
  }
  const gathering = await repo.find(id)
  if (!gathering) throw new UseCaseError(404, '見つかりません')
  return gathering
}
