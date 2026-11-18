import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1RecommendationRepository } from '../../infrastructure/db/socialRepository'
import { listRecommendations } from '../../application/social'
import { UseCaseError } from '../../application/errors'

// おすすめの店（追加・削除は /residents/me/recommendations。residentSocial.ts）。要ログイン
export const recommendationsRoute = new Hono<AppEnv>()
recommendationsRoute.use('*', requireAuth)

recommendationsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /recommendations?genre=&q= — みんなのおすすめの店（投稿者つき・新しい順）
recommendationsRoute.get('/', async (c) => {
  const recommendations = await listRecommendations(new D1RecommendationRepository(c.env.DB), {
    genre: c.req.query('genre'),
    q: c.req.query('q'),
  })
  return c.json({ recommendations })
})
