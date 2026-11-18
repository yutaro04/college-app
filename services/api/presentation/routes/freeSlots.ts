import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1FreeSlotRepository } from '../../infrastructure/db/socialRepository'
import { listEveryonesFreeSlots } from '../../application/social'
import { UseCaseError } from '../../application/errors'

// 空き時間（本人の登録・削除と個人ページ用は /residents/... 。residentSocial.ts）。要ログイン
export const freeSlotsRoute = new Hono<AppEnv>()
freeSlotsRoute.use('*', requireAuth)

freeSlotsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /free-slots?from=&to= — 指定時間帯をまるごと空けている人の一覧（ひま募集の相手探し用）。
// 期間省略時は全員の今から 7 日分。どちらも自分の分は除く
freeSlotsRoute.get('/', async (c) => {
  const slots = await listEveryonesFreeSlots(new D1FreeSlotRepository(c.env.DB), c.get('auth').residentId, {
    from: c.req.query('from'),
    to: c.req.query('to'),
  })
  return c.json({ slots })
})
