import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1HimaRepository } from '../../infrastructure/db/himaRepository'
import { inviteToHima, postHimaStatus } from '../../application/hima'
import { UseCaseError } from '../../application/errors'

// いまひま（旧 Supabase の availability / availability_invites）。すべて要ログイン
export const himaStatusesRoute = new Hono<AppEnv>()
himaStatusesRoute.use('*', requireAuth)

himaStatusesRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /hima-statuses — 期限内の表明（新しい順）
himaStatusesRoute.get('/', async (c) => {
  const statuses = await new D1HimaRepository(c.env.DB).listActive(new Date().toISOString())
  return c.json({ statuses })
})

// PUT /hima-statuses/me — {message, expiresAt} 表明する（既存の表明と、それへの誘いは消える）
himaStatusesRoute.put('/me', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const status = await postHimaStatus(new D1HimaRepository(c.env.DB), c.get('auth').residentId, body)
  return c.json({ status })
})

// DELETE /hima-statuses/me — 表明を取り下げる
himaStatusesRoute.delete('/me', async (c) => {
  await new D1HimaRepository(c.env.DB).clear(c.get('auth').residentId)
  return c.body(null, 204)
})

// GET /hima-statuses/me/invites — 自分の表明に届いた誘い（新しい順・最大 50 件）
himaStatusesRoute.get('/me/invites', async (c) => {
  const invites = await new D1HimaRepository(c.env.DB).listInvitesFor(c.get('auth').residentId, 50)
  return c.json({ invites })
})

// POST /hima-statuses/:id/invites — {message} 誘う
himaStatusesRoute.post('/:id/invites', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const invite = await inviteToHima(new D1HimaRepository(c.env.DB), c.get('auth').residentId, c.req.param('id'), body)
  return c.json({ invite }, 201)
})
