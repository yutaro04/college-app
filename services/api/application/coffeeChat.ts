import {
  COFFEE_CHAT_MESSAGE_MAX,
  type CoffeeChatAction,
  type CoffeeChatRequestRepository,
  type CoffeeChatRequestStatus,
  type CoffeeChatRequestView,
} from '../domain/coffeeChatRequest'
import type { ResidentRepository } from '../domain/resident'
import { UseCaseError } from './errors'

const STATUSES: CoffeeChatRequestStatus[] = ['pending', 'accepted', 'declined', 'cancelled']

export async function listCoffeeChatRequests(
  repo: CoffeeChatRequestRepository,
  residentId: string,
  box: string | undefined,
  status: string | undefined
): Promise<CoffeeChatRequestView[]> {
  const b = box ?? 'received'
  if (b !== 'sent' && b !== 'received') throw new UseCaseError(400, 'box は sent か received です')
  const s = status ? STATUSES.find((x) => x === status) : null
  if (s === undefined) throw new UseCaseError(400, 'status が不正です')
  return repo.list(residentId, b, s)
}

export async function requestCoffeeChat(
  deps: { requests: CoffeeChatRequestRepository; residents: ResidentRepository },
  residentId: string,
  body: { recipientId?: unknown; message?: unknown }
): Promise<CoffeeChatRequestView> {
  const recipientId = typeof body.recipientId === 'string' ? body.recipientId : ''
  if (!recipientId || !(await deps.residents.findProfile(recipientId))) {
    throw new UseCaseError(400, '申請先が見つかりません')
  }
  if (recipientId === residentId) throw new UseCaseError(400, '自分には申請できません')
  const message = typeof body.message === 'string' ? body.message.trim() : ''
  if (message.length > COFFEE_CHAT_MESSAGE_MAX) {
    throw new UseCaseError(400, `メッセージは${COFFEE_CHAT_MESSAGE_MAX}文字以内にしてください`)
  }
  if (await deps.requests.hasPendingBetween(residentId, recipientId)) {
    throw new UseCaseError(409, 'すでに返事待ちの申請があります')
  }
  const id = await deps.requests.create(residentId, recipientId, message || null).catch((e: unknown) => {
    // 同時に申請した場合は一意制約（uniq_coffee_chat_pending_pair）で弾かれる
    if (e instanceof Error && e.message.includes('UNIQUE')) throw new UseCaseError(409, 'すでに返事待ちの申請があります')
    throw e
  })
  return (await deps.requests.find(id))!
}

// 承諾・見送りは受け取った側、取り消しは送った側だけができる
export async function respondCoffeeChat(
  repo: CoffeeChatRequestRepository,
  residentId: string,
  id: string,
  action: unknown
): Promise<CoffeeChatRequestView> {
  const request = await repo.find(id)
  // 当事者でなければ存在自体を明かさない
  if (!request || (request.requesterId !== residentId && request.recipientId !== residentId)) {
    throw new UseCaseError(404, '申請が見つかりません')
  }
  const next = nextStatus(action as CoffeeChatAction, request, residentId)
  if (!next) throw new UseCaseError(403, 'この操作はできません')
  if (request.status !== 'pending' || !(await repo.transition(id, next))) {
    throw new UseCaseError(409, 'この申請はすでに処理済みです')
  }
  return (await repo.find(id))!
}

function nextStatus(
  action: CoffeeChatAction,
  request: CoffeeChatRequestView,
  residentId: string
): CoffeeChatRequestStatus | null {
  switch (action) {
    case 'accept':
      return request.recipientId === residentId ? 'accepted' : null
    case 'decline':
      return request.recipientId === residentId ? 'declined' : null
    case 'cancel':
      return request.requesterId === residentId ? 'cancelled' : null
    default:
      return null
  }
}
