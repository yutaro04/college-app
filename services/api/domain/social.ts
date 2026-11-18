export type RecommendationGenre = 'cafe' | 'restaurant' | 'bar' | 'shop' | 'other'

export interface ResidentRecommendation {
  id: string
  residentId: string
  name: string
  genre: RecommendationGenre
  area: string | null
  comment: string | null
  url: string | null
  createdAt: string
}

export type ResidentLikeKind = 'like' | 'pass'

export interface ResidentLike {
  fromResidentId: string
  toResidentId: string
  kind: ResidentLikeKind
  topic: string | null
  createdAt: string
}

export interface InviteWish {
  id: string
  residentId: string
  title: string
  note: string | null
  createdAt: string
}

export interface InviteWishInvitation {
  id: string
  wishId: string
  inviterResidentId: string
  message: string
  createdAt: string
}

export interface ResidentFreeSlot {
  id: string
  residentId: string
  startsAt: string
  endsAt: string
  note: string | null
  createdAt: string
}

export interface HimaGathering {
  id: string
  hostResidentId: string
  title: string
  location: string | null
  startsAt: string
  endsAt: string
  capacity: number | null
  note: string | null
  createdAt: string
  cancelledAt: string | null
}

/**
 * 匿名文通のスレッド。residentId 系はサーバー内部でのみ使い、API レスポンスには
 * 自分から見た alias（myAlias / partnerAlias）だけを返すこと。
 */
export interface PenPalThread {
  id: string
  starterResidentId: string
  partnerResidentId: string
  starterAlias: string
  partnerAlias: string
  createdAt: string
  closedAt: string | null
}

export interface PenPalLetter {
  id: string
  threadId: string
  senderResidentId: string
  body: string
  createdAt: string
  readAt: string | null
}
