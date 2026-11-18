import type { Context } from 'hono'
import type { AppEnv } from '../env'
import {
  D1FreeSlotRepository,
  D1InviteWishRepository,
  D1RecommendationRepository,
} from '../../infrastructure/db/socialRepository'
import {
  addFreeSlot,
  addInviteWish,
  addRecommendation,
  deleteFreeSlot,
  deleteInviteWish,
  deleteRecommendation,
  listResidentFreeSlots,
} from '../../application/social'
import { UseCaseError } from '../../application/errors'

// /residents 配下の交流機能（おすすめの店・誘って・空き時間）のハンドラ。
// ルーティングは residents.ts（/me/... を /:id/... より先に登録するため）。どれも requireAuth の後ろで使う

type Ctx = Context<AppEnv>

async function run(c: Ctx, fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn()
  } catch (e) {
    if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
    throw e
  }
}

async function jsonBody(c: Ctx): Promise<Record<string, unknown>> {
  return (await c.req.json().catch(() => ({}))) as Record<string, unknown>
}

// POST /residents/me/recommendations — {name, genre, area?, comment?, url?}
export const postMyRecommendation = (c: Ctx) =>
  run(c, async () => {
    const recommendation = await addRecommendation(
      new D1RecommendationRepository(c.env.DB),
      c.get('auth').residentId,
      await jsonBody(c)
    )
    return c.json({ recommendation }, 201)
  })

// DELETE /residents/me/recommendations/:recommendationId — 本人のものだけ消せる（他人のものは 404）
export const deleteMyRecommendation = (c: Ctx) =>
  run(c, async () => {
    await deleteRecommendation(
      new D1RecommendationRepository(c.env.DB),
      c.get('auth').residentId,
      c.req.param('recommendationId') ?? ''
    )
    return c.body(null, 204)
  })

// GET /residents/:id/recommendations — その人のおすすめの店（新しい順）
export const getResidentRecommendations = (c: Ctx) =>
  run(c, async () => {
    const recommendations = await new D1RecommendationRepository(c.env.DB).listByResident(c.req.param('id') ?? '')
    return c.json({ recommendations })
  })

// POST /residents/me/invite-wishes — {title, note?}
export const postMyInviteWish = (c: Ctx) =>
  run(c, async () => {
    const wish = await addInviteWish(new D1InviteWishRepository(c.env.DB), c.get('auth').residentId, await jsonBody(c))
    return c.json({ wish }, 201)
  })

// DELETE /residents/me/invite-wishes/:wishId — 本人のものだけ消せる（他人のものは 404）
export const deleteMyInviteWish = (c: Ctx) =>
  run(c, async () => {
    await deleteInviteWish(new D1InviteWishRepository(c.env.DB), c.get('auth').residentId, c.req.param('wishId') ?? '')
    return c.body(null, 204)
  })

// POST /residents/me/free-slots — {startsAt, endsAt, note?}
export const postMyFreeSlot = (c: Ctx) =>
  run(c, async () => {
    const slot = await addFreeSlot(new D1FreeSlotRepository(c.env.DB), c.get('auth').residentId, await jsonBody(c))
    return c.json({ slot }, 201)
  })

// DELETE /residents/me/free-slots/:slotId — 本人のものだけ消せる（他人のものは 404）
export const deleteMyFreeSlot = (c: Ctx) =>
  run(c, async () => {
    await deleteFreeSlot(new D1FreeSlotRepository(c.env.DB), c.get('auth').residentId, c.req.param('slotId') ?? '')
    return c.body(null, 204)
  })

// GET /residents/:id/free-slots?from=&to= — その人の空き時間（既定は今から 7 日間）
export const getResidentFreeSlots = (c: Ctx) =>
  run(c, async () => {
    const slots = await listResidentFreeSlots(new D1FreeSlotRepository(c.env.DB), c.req.param('id') ?? '', {
      from: c.req.query('from'),
      to: c.req.query('to'),
    })
    return c.json({ slots })
  })
