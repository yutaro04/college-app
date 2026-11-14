import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const residentsRoute = new Hono<{ Bindings: Env }>()

// GET /residents/matches — 要ログイン。共有属性数の多い順。
// :id より先に登録し、"matches" が :id にマッチしないようにする。
residentsRoute.get('/matches', notImplemented)

// GET /residents — 図鑑一覧。?attributeId= / ?categoryKey= / ?q= / ?cursor=
residentsRoute.get('/', notImplemented)

// GET /residents/:id — 詳細（属性一覧込み）
residentsRoute.get('/:id', notImplemented)

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
