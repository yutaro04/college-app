import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1HimaGatheringRepository } from '../../infrastructure/db/socialRepository'
import { cancelHimaGathering, createHimaGathering, setHimaGatheringJoined } from '../../application/social'
import { UseCaseError } from '../../application/errors'

// ひま募集（時間指定で人を集める）。要ログイン
export const himaGatheringsRoute = new Hono<AppEnv>()
himaGatheringsRoute.use('*', requireAuth)

himaGatheringsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /hima-gatherings — これからのひま募集（主催者・参加者つき、開始順）
himaGatheringsRoute.get('/', async (c) => {
  const gatherings = await new D1HimaGatheringRepository(c.env.DB).listUpcoming(new Date().toISOString())
  return c.json({ gatherings })
})

// POST /hima-gatherings — {title, location?, startsAt, endsAt, capacity?, note?}
himaGatheringsRoute.post('/', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const gathering = await createHimaGathering(new D1HimaGatheringRepository(c.env.DB), c.get('auth').residentId, body)
  return c.json({ gathering }, 201)
})

// DELETE /hima-gatherings/:id — 主催者による取り消し（cancelled_at を立てる）
himaGatheringsRoute.delete('/:id', async (c) => {
  await cancelHimaGathering(new D1HimaGatheringRepository(c.env.DB), c.get('auth').residentId, c.req.param('id'))
  return c.body(null, 204)
})

// POST /hima-gatherings/:id/join — 参加（定員超過は 409）→ {gathering}
himaGatheringsRoute.post('/:id/join', async (c) => {
  const repo = new D1HimaGatheringRepository(c.env.DB)
  const gathering = await setHimaGatheringJoined(repo, c.get('auth').residentId, c.req.param('id'), true)
  return c.json({ gathering })
})

// DELETE /hima-gatherings/:id/join — 参加取り消し → {gathering}
himaGatheringsRoute.delete('/:id/join', async (c) => {
  const repo = new D1HimaGatheringRepository(c.env.DB)
  const gathering = await setHimaGatheringJoined(repo, c.get('auth').residentId, c.req.param('id'), false)
  return c.json({ gathering })
})
