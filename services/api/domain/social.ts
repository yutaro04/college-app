// 交流機能（おすすめの店 / 気になる / 「〇〇あったら誘って」 / 空き時間 / ひま募集 / 匿名文通）
// ここの型は API が返す形（iOS の Domain/Social.swift と同じ camelCase）。テーブルは 0003_social.sql

import type { ResidentSummary } from './hima'

export type { ResidentSummary }

export interface AttributeTag {
  id: string
  categoryKey: string
  value: string
}

// 属性一覧込みの居住者（iOS の `Resident` と同じ形）
export interface ResidentWithAttributes {
  id: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
  attributes: AttributeTag[]
}

// MARK: - おすすめの店

export const RECOMMENDATION_GENRES = ['cafe', 'restaurant', 'bar', 'shop', 'other'] as const
export type RecommendationGenre = (typeof RECOMMENDATION_GENRES)[number]

export interface Recommendation {
  id: string
  name: string
  genre: RecommendationGenre
  area: string | null
  comment: string | null
  url: string | null
  createdAt: string
  // 投稿者
  resident: ResidentSummary
}

export interface NewRecommendation {
  name: string
  genre: RecommendationGenre
  area: string | null
  comment: string | null
  url: string | null
}

export interface RecommendationRepository {
  list(filter: { genre?: RecommendationGenre; q?: string }, limit: number): Promise<Recommendation[]>
  listByResident(residentId: string): Promise<Recommendation[]>
  create(residentId: string, input: NewRecommendation, now: string): Promise<Recommendation>
  // 本人のものだけ消す。消せたら true
  delete(residentId: string, id: string): Promise<boolean>
}

// MARK: - 気になる（マチアプ風の相互いいね）

export type ResidentLikeKind = 'like' | 'pass'

// GET /likes/discover の 1 件（iOS の ResidentMatch と同じ形）
export interface LikeCandidate {
  resident: ResidentWithAttributes
  sharedAttributes: AttributeTag[]
}

// 相互に like した相手。片思いの相手はここに出てこない
export interface LikeMatch {
  resident: ResidentSummary
  // 自分が相手のどこに興味を持ったか
  myTopic: string | null
  // 相手が自分のどこに興味を持ったか
  theirTopic: string | null
  matchedAt: string
}

export interface LikeRepository {
  residentExists(residentId: string): Promise<boolean>
  // まだ振り分けていない人（自分以外）を属性つきで返す。並べ替えはユースケース側
  listUndecided(residentId: string): Promise<ResidentWithAttributes[]>
  myAttributeIds(residentId: string): Promise<string[]>
  // 振り分けを記録（同じ相手は上書き）し、相手からも like されていれば true
  upsert(from: string, to: string, kind: ResidentLikeKind, topic: string | null, now: string): Promise<boolean>
  listMatches(residentId: string): Promise<LikeMatch[]>
  countReceived(residentId: string): Promise<number>
}

// MARK: - 〇〇あったら誘って

export interface InviteWish {
  id: string
  title: string
  note: string | null
  createdAt: string
  resident: ResidentSummary
}

// 自分の「誘って」に届いた誘い
export interface WishInvitation {
  id: string
  wishTitle: string
  message: string
  createdAt: string
  inviter: ResidentSummary
}

export interface InviteWishRepository {
  list(filter: { residentId?: string; q?: string }, limit: number): Promise<InviteWish[]>
  findOwner(wishId: string): Promise<string | null>
  create(residentId: string, title: string, note: string | null, now: string): Promise<InviteWish>
  delete(residentId: string, id: string): Promise<boolean>
  addInvitation(wishId: string, inviterId: string, message: string, now: string): Promise<{ id: string; createdAt: string }>
  listInvitationsFor(residentId: string, limit: number): Promise<WishInvitation[]>
}

// MARK: - 空き時間

export interface FreeSlot {
  id: string
  startsAt: string
  endsAt: string
  note: string | null
  // GET /free-slots のように複数人分を返すときだけ入る
  resident?: ResidentSummary
}

export interface FreeSlotRepository {
  // その人の空き時間のうち [from, to) と重なるもの
  listByResident(residentId: string, from: string, to: string): Promise<FreeSlot[]>
  // 自分以外の空き時間のうち [from, to) と重なるもの
  listOverlapping(excludeResidentId: string, from: string, to: string): Promise<FreeSlot[]>
  // 自分以外の空き時間のうち [from, to] をまるごと含むもの
  listCovering(excludeResidentId: string, from: string, to: string): Promise<FreeSlot[]>
  create(residentId: string, startsAt: string, endsAt: string, note: string | null, now: string): Promise<FreeSlot>
  delete(residentId: string, id: string): Promise<boolean>
}

// MARK: - ひま募集

export interface HimaGathering {
  id: string
  title: string
  location: string | null
  startsAt: string
  endsAt: string
  capacity: number | null
  note: string | null
  host: ResidentSummary
  participants: ResidentSummary[]
}

export interface NewHimaGathering {
  title: string
  location: string | null
  startsAt: string
  endsAt: string
  capacity: number | null
  note: string | null
}

export interface HimaGatheringRepository {
  // 取り消されておらず、まだ終わっていないもの（開始順）
  listUpcoming(now: string): Promise<HimaGathering[]>
  find(id: string): Promise<HimaGathering | null>
  findState(id: string): Promise<{ hostId: string; endsAt: string; cancelled: boolean } | null>
  create(hostId: string, input: NewHimaGathering, now: string): Promise<HimaGathering>
  cancel(id: string, now: string): Promise<void>
  // 定員に空きがあるときだけ参加させる。参加済み、または参加できたら true
  join(id: string, residentId: string, now: string): Promise<boolean>
  leave(id: string, residentId: string): Promise<void>
}

// MARK: - 匿名文通

/**
 * 自分から見たスレッド。相手の resident id・名前は絶対に含めない（ペンネームだけ）。
 * リポジトリの SQL でも相手の resident_id を SELECT しないこと（fromMe などは SQL 内で計算する）
 */
export interface PenPalThread {
  id: string
  myAlias: string
  partnerAlias: string
  createdAt: string
  closedAt: string | null
  lastLetter: PenPalLetter | null
  unreadCount: number
}

export interface PenPalLetter {
  id: string
  fromMe: boolean
  body: string
  createdAt: string
}

export interface PenPalRepository {
  listThreads(residentId: string): Promise<PenPalThread[]>
  findThread(residentId: string, threadId: string): Promise<PenPalThread | null>
  // 手紙を受け取れる相手をランダムに 1 人選ぶ（自分・進行中の相手・通報が絡んだ相手は除く）
  pickPartner(residentId: string): Promise<string | null>
  start(
    starterId: string,
    partnerId: string,
    aliases: { starter: string; partner: string },
    body: string,
    now: string
  ): Promise<string>
  // 相手からの未読の手紙を既読にしてから一覧を返す
  readLetters(residentId: string, threadId: string, now: string): Promise<PenPalLetter[]>
  addLetter(residentId: string, threadId: string, body: string, now: string): Promise<PenPalLetter>
  close(threadId: string, now: string): Promise<void>
  report(residentId: string, threadId: string, reason: string | null, now: string): Promise<void>
}

export const PEN_NAMES = [
  '夜更かしのフクロウ', '春の風見鶏', '迷子の灯台', 'ひなたぼっこ', '雨上がりの猫',
  '真夜中のパン屋', '旅するペンギン', '静かな本棚', '月見団子', '青いポスト',
  '午後の紅茶係', '星を数える人', '屋根の上のバイオリン', '海辺の郵便屋', '眠れる森のリス',
  '朝焼けの自転車', '小さな灯り', '風まかせのタンポポ', '金曜日のカレー', '遠くの汽笛',
]

// 入力の上限
export const SOCIAL_LIMITS = {
  recommendationName: 100,
  recommendationArea: 100,
  recommendationComment: 500,
  url: 500,
  likeTopic: 100,
  wishTitle: 100,
  wishNote: 500,
  invitationMessage: 500,
  slotNote: 200,
  gatheringTitle: 100,
  gatheringLocation: 100,
  gatheringNote: 500,
  gatheringCapacity: 100,
  penPalLetter: 2000,
  penPalReport: 1000,
  query: 100,
} as const
