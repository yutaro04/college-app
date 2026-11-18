import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { searchAttributes } from '../../application/directory'
import { D1AttributeRepository } from '../../infrastructure/db/attributeRepository'

export const attributesRoute = new Hono<AppEnv>()
attributesRoute.use('*', requireAuth)

// GET /attributes?categoryKey=&q= — 既存タグの検索・オートコンプリート（使っている人が多い順・最大 100 件）
attributesRoute.get('/', async (c) => {
  const attributes = await searchAttributes(
    new D1AttributeRepository(c.env.DB),
    c.req.query('categoryKey') || null,
    c.req.query('q') ?? ''
  )
  return c.json({ attributes })
})
