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
