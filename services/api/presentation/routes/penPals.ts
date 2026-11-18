import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1PenPalRepository } from '../../infrastructure/db/penPalRepository'
import { readPenPalLetters, reportPenPal, sendPenPalLetter, startPenPal, updatePenPal } from '../../application/penPals'
import { UseCaseError } from '../../application/errors'

// 匿名文通。レスポンスには相手の resident_id / 表示名を絶対に含めないこと（ペンネームのみ）。
// 自分が当事者でないスレッドはすべて 404（存在の有無も明かさない）。要ログイン
export const penPalsRoute = new Hono<AppEnv>()
penPalsRoute.use('*', requireAuth)

penPalsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /pen-pals — 自分のスレッド一覧（myAlias / partnerAlias / 最新の手紙 / 未読数。最近やりとりした順）
penPalsRoute.get('/', async (c) => {
  const threads = await new D1PenPalRepository(c.env.DB).listThreads(c.get('auth').residentId)
  return c.json({ threads })
})

// POST /pen-pals — {body}。ランダムな相手を選んでスレッドを作り、最初の手紙を送る
penPalsRoute.post('/', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const thread = await startPenPal(new D1PenPalRepository(c.env.DB), c.get('auth').residentId, body)
  return c.json({ thread }, 201)
})

// GET /pen-pals/:id/letters — 手紙一覧（古い順。取得時に相手からの手紙を既読にする）
penPalsRoute.get('/:id/letters', async (c) => {
  const letters = await readPenPalLetters(new D1PenPalRepository(c.env.DB), c.get('auth').residentId, c.req.param('id'))
  return c.json({ letters })
})

// POST /pen-pals/:id/letters — {body} で返事を書く（終了した文通には 409）
penPalsRoute.post('/:id/letters', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const repo = new D1PenPalRepository(c.env.DB)
  const letter = await sendPenPalLetter(repo, c.get('auth').residentId, c.req.param('id'), body)
  return c.json({ letter }, 201)
})

// PATCH /pen-pals/:id — {action: "close"} で文通を終える → {thread}
penPalsRoute.patch('/:id', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const thread = await updatePenPal(new D1PenPalRepository(c.env.DB), c.get('auth').residentId, c.req.param('id'), body)
  return c.json({ thread })
})

// POST /pen-pals/:id/report — {reason?} 運営へ通報
penPalsRoute.post('/:id/report', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  await reportPenPal(new D1PenPalRepository(c.env.DB), c.get('auth').residentId, c.req.param('id'), body)
  return c.json({}, 201)
})
