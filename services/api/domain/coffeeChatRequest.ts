import type { ResidentRef } from './resident'

export type CoffeeChatRequestStatus = 'pending' | 'accepted' | 'declined' | 'cancelled'

export interface CoffeeChatRequest {
  id: string
  requesterId: string
  recipientId: string
  status: CoffeeChatRequestStatus
  message: string | null
  createdAt: string
  respondedAt: string | null
}

export type CoffeeChatAction = 'accept' | 'decline' | 'cancel'

// API が返す申請（双方の最小情報つき）。iOS の `CoffeeChatRequest` と同じ形
export interface CoffeeChatRequestView extends CoffeeChatRequest {
  requester: ResidentRef
  recipient: ResidentRef
}

export interface CoffeeChatRequestRepository {
  find(id: string): Promise<CoffeeChatRequestView | null>
  list(residentId: string, box: 'sent' | 'received', status: CoffeeChatRequestStatus | null): Promise<CoffeeChatRequestView[]>
  // どちら向きでも、2 人の間に返事待ちの申請があるか
  hasPendingBetween(a: string, b: string): Promise<boolean>
  create(requesterId: string, recipientId: string, message: string | null): Promise<string>
  // 返事待ちのときだけ状態を変える。変えられなければ false（先に誰かが処理した）
  transition(id: string, status: CoffeeChatRequestStatus): Promise<boolean>
}

export const COFFEE_CHAT_MESSAGE_MAX = 500
