import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { notImplemented } from './_notImplemented'
import { requireAuth } from '../middleware/auth'
import { D1ResidentRepository } from '../../infrastructure/db/residentRepository'
import { updateMyProfile } from '../../application/updateMyProfile'
import { UseCaseError } from '../../application/errors'
import { addMyAttribute, getResident, listMatches, searchResidents } from '../../application/directory'
import { D1AttributeRepository } from '../../infrastructure/db/attributeRepository'
import {
  deleteMyFreeSlot,
  deleteMyInviteWish,
  deleteMyRecommendation,
  getResidentFreeSlots,
  getResidentRecommendations,
  postMyFreeSlot,
  postMyInviteWish,
  postMyRecommendation,
} from './residentSocial'

export const residentsRoute = new Hono<AppEnv>()
// 図鑑は寮生の個人情報なので、すべて要ログイン
residentsRoute.use('*', requireAuth)

residentsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /residents/matches — 要ログイン。共有属性数の多い順。
// :id より先に登録し、"matches" が :id にマッチしないようにする。
residentsRoute.get('/matches', async (c) => {
  const matches = await listMatches(new D1ResidentRepository(c.env.DB), c.get('auth').residentId)
  return c.json({ matches })
})

// GET /residents — 図鑑一覧（名前順・最大 300 人）。?attributeId=（複数可・OR）/ ?categoryKey= / ?q=（名前・タグの部分一致）
residentsRoute.get('/', async (c) => {
  const residents = await searchResidents(new D1ResidentRepository(c.env.DB), {
    q: c.req.query('q') ?? '',
    attributeIds: c.req.queries('attributeId') ?? [],
    categoryKey: c.req.query('categoryKey') || null,
  })
  return c.json({ residents })
})

// 「/me/...」は「/:id/...」と衝突するので、:id 系より先に登録する

// POST /residents/me/recommendations — おすすめの店を追加
residentsRoute.post('/me/recommendations', postMyRecommendation)
// DELETE /residents/me/recommendations/:recommendationId
residentsRoute.delete('/me/recommendations/:recommendationId', deleteMyRecommendation)

// POST /residents/me/invite-wishes — {title, note?}「〇〇あったら誘って」を追加
residentsRoute.post('/me/invite-wishes', postMyInviteWish)
// DELETE /residents/me/invite-wishes/:wishId
residentsRoute.delete('/me/invite-wishes/:wishId', deleteMyInviteWish)

// POST /residents/me/free-slots — {startsAt, endsAt, note?} 空き時間を登録
residentsRoute.post('/me/free-slots', postMyFreeSlot)
// DELETE /residents/me/free-slots/:slotId
residentsRoute.delete('/me/free-slots/:slotId', deleteMyFreeSlot)

// GET /residents/:id — 詳細（属性一覧込み）
residentsRoute.get('/:id', async (c) => {
  const resident = await getResident(new D1ResidentRepository(c.env.DB), c.req.param('id'))
  return c.json({ resident })
})
// GET /residents/:id/recommendations — その人のおすすめの店
residentsRoute.get('/:id/recommendations', getResidentRecommendations)
// GET /residents/:id/free-slots?from=&to= — その人の空き時間（既定は今から 7 日間）
residentsRoute.get('/:id/free-slots', getResidentFreeSlots)

// PATCH /residents/me — 自分のプロフィール更新 {displayName?, bio?}
residentsRoute.patch('/me', requireAuth, async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  try {
    const resident = await updateMyProfile(new D1ResidentRepository(c.env.DB), c.get('auth').residentId, body)
    return c.json({ resident })
  } catch (e) {
    if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
    throw e
  }
})

// GET /residents/:id/photos?kind= — 写真一覧
residentsRoute.get('/:id/photos', notImplemented)
// POST /residents/me/photos — multipart アップロードして ResidentPhoto 作成
residentsRoute.post('/me/photos', notImplemented)
// DELETE /residents/me/photos/:photoId
residentsRoute.delete('/me/photos/:photoId', notImplemented)

// GET /residents/me/attributes — 自分が持つ属性一覧
residentsRoute.get('/me/attributes', async (c) => {
  const attributes = await new D1AttributeRepository(c.env.DB).listOf(c.get('auth').residentId)
  return c.json({ attributes })
})
// POST /residents/me/attributes — {categoryKey, value} で find-or-create して紐付け
residentsRoute.post('/me/attributes', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const attribute = await addMyAttribute(new D1AttributeRepository(c.env.DB), c.get('auth').residentId, body)
  return c.json({ attribute }, 201)
})
// DELETE /residents/me/attributes/:attributeId
residentsRoute.delete('/me/attributes/:attributeId', async (c) => {
  await new D1AttributeRepository(c.env.DB).detach(c.get('auth').residentId, c.req.param('attributeId'))
  return c.body(null, 204)
})
