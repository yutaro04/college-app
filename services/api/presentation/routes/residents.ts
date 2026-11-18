import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const residentsRoute = new Hono<{ Bindings: Env }>()

// GET /residents/matches — 要ログイン。共有属性数の多い順。
// :id より先に登録し、"matches" が :id にマッチしないようにする。
residentsRoute.get('/matches', notImplemented)

// GET /residents — 図鑑一覧。?attributeId= / ?categoryKey= / ?q= / ?cursor=
residentsRoute.get('/', notImplemented)

// 「/me/...」は「/:id/...」と衝突するので、:id 系より先に登録する

// POST /residents/me/recommendations — おすすめの店を追加
residentsRoute.post('/me/recommendations', notImplemented)
// DELETE /residents/me/recommendations/:recommendationId
residentsRoute.delete('/me/recommendations/:recommendationId', notImplemented)

// POST /residents/me/invite-wishes — {title, note?}「〇〇あったら誘って」を追加
residentsRoute.post('/me/invite-wishes', notImplemented)
// DELETE /residents/me/invite-wishes/:wishId
residentsRoute.delete('/me/invite-wishes/:wishId', notImplemented)

// POST /residents/me/free-slots — {startsAt, endsAt, note?} 空き時間を登録
residentsRoute.post('/me/free-slots', notImplemented)
// DELETE /residents/me/free-slots/:slotId
residentsRoute.delete('/me/free-slots/:slotId', notImplemented)

// GET /residents/:id — 詳細（属性一覧込み）
residentsRoute.get('/:id', notImplemented)
// GET /residents/:id/recommendations — その人のおすすめの店
residentsRoute.get('/:id/recommendations', notImplemented)
// GET /residents/:id/free-slots?from=&to= — その人の空き時間（既定は今日から 7 日間）
residentsRoute.get('/:id/free-slots', notImplemented)

// PATCH /residents/me — 自分のプロフィール更新
residentsRoute.patch('/me', notImplemented)

// GET /residents/:id/photos?kind= — 写真一覧
residentsRoute.get('/:id/photos', notImplemented)
// POST /residents/me/photos — multipart アップロードして ResidentPhoto 作成
residentsRoute.post('/me/photos', notImplemented)
// DELETE /residents/me/photos/:photoId
residentsRoute.delete('/me/photos/:photoId', notImplemented)

// GET /residents/me/attributes — 自分が持つ属性一覧
residentsRoute.get('/me/attributes', notImplemented)
// POST /residents/me/attributes — {categoryKey, value} で find-or-create して紐付け
residentsRoute.post('/me/attributes', notImplemented)
// DELETE /residents/me/attributes/:attributeId
residentsRoute.delete('/me/attributes/:attributeId', notImplemented)
