import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { UseCaseError } from '../../application/errors'
import { listCoffeeChatRequests, requestCoffeeChat, respondCoffeeChat } from '../../application/coffeeChat'
import { D1CoffeeChatRequestRepository } from '../../infrastructure/db/coffeeChatRequestRepository'
import { D1ResidentRepository } from '../../infrastructure/db/residentRepository'

export const coffeeChatRequestsRoute = new Hono<AppEnv>()
coffeeChatRequestsRoute.use('*', requireAuth)

coffeeChatRequestsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// POST /coffee-chat-requests — {recipientId, message?} で申請作成。2 人の間に返事待ちがあれば 409
coffeeChatRequestsRoute.post('/', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const request = await requestCoffeeChat(
    { requests: new D1CoffeeChatRequestRepository(c.env.DB), residents: new D1ResidentRepository(c.env.DB) },
    c.get('auth').residentId,
    body
  )
  return c.json({ request }, 201)
})

// GET /coffee-chat-requests?box=sent|received&status= — 送信/受信した申請一覧（新しい順）
coffeeChatRequestsRoute.get('/', async (c) => {
  const requests = await listCoffeeChatRequests(
    new D1CoffeeChatRequestRepository(c.env.DB),
    c.get('auth').residentId,
    c.req.query('box'),
    c.req.query('status')
  )
  return c.json({ requests })
})

// PATCH /coffee-chat-requests/:id — {action: "accept" | "decline" | "cancel"}。承諾・見送りは受け取った側、取り消しは送った側
coffeeChatRequestsRoute.patch('/:id', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const request = await respondCoffeeChat(
    new D1CoffeeChatRequestRepository(c.env.DB),
    c.get('auth').residentId,
    c.req.param('id'),
    body.action
  )
  return c.json({ request })
})
