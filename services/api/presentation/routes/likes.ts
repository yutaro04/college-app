import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1LikeRepository } from '../../infrastructure/db/socialRepository'
import { discoverCandidates, putLike } from '../../application/social'
import { UseCaseError } from '../../application/errors'

// 気になる（マチアプ風の相互いいね）。片思いの相手は返さない（人数だけ）。要ログイン
export const likesRoute = new Hono<AppEnv>()
likesRoute.use('*', requireAuth)

likesRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /likes/discover — まだ振り分けていない人を共通属性の多い順に返す（カード用）
likesRoute.get('/discover', async (c) => {
  const candidates = await discoverCandidates(new D1LikeRepository(c.env.DB), c.get('auth').residentId)
  return c.json({ candidates })
})

// GET /likes/matches — 相互に「気になる」した相手（お互いの topic つき）
likesRoute.get('/matches', async (c) => {
  const matches = await new D1LikeRepository(c.env.DB).listMatches(c.get('auth').residentId)
  return c.json({ matches })
})

// GET /likes/received-count — 自分を「気になる」した人数（相手は明かさない）
likesRoute.get('/received-count', async (c) => {
  const count = await new D1LikeRepository(c.env.DB).countReceived(c.get('auth').residentId)
  return c.json({ count })
})

// PUT /likes/:residentId — {kind: "like" | "pass", topic?} → {matched}
likesRoute.put('/:residentId', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const result = await putLike(new D1LikeRepository(c.env.DB), c.get('auth').residentId, c.req.param('residentId'), body)
  return c.json(result)
})
