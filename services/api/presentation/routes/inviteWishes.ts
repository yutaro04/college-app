import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1InviteWishRepository } from '../../infrastructure/db/socialRepository'
import { inviteForWish, listInviteWishes } from '../../application/social'
import { UseCaseError } from '../../application/errors'

// 「〇〇あったら誘って」（追加・削除は /residents/me/invite-wishes。residentSocial.ts）。要ログイン
export const inviteWishesRoute = new Hono<AppEnv>()
inviteWishesRoute.use('*', requireAuth)

inviteWishesRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /invite-wishes?q=&residentId= — 一覧（新しい順）
inviteWishesRoute.get('/', async (c) => {
  const wishes = await listInviteWishes(new D1InviteWishRepository(c.env.DB), {
    residentId: c.req.query('residentId'),
    q: c.req.query('q'),
  })
  return c.json({ wishes })
})

// GET /invite-wishes/invitations — 自分の「誘って」に届いた誘い（新しい順・最大 50 件）
inviteWishesRoute.get('/invitations', async (c) => {
  const invitations = await new D1InviteWishRepository(c.env.DB).listInvitationsFor(c.get('auth').residentId, 50)
  return c.json({ invitations })
})

// POST /invite-wishes/:id/invitations — {message} で誘う。自分の「誘って」には誘えない
inviteWishesRoute.post('/:id/invitations', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const invitation = await inviteForWish(
    new D1InviteWishRepository(c.env.DB),
    c.get('auth').residentId,
    c.req.param('id'),
    body
  )
  return c.json({ invitation }, 201)
})
