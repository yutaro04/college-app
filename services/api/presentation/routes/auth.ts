import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const authRoute = new Hono<{ Bindings: Env }>()

// GET /auth/google/start — Google OAuth 開始（リダイレクト）
authRoute.get('/google/start', notImplemented)
// GET /auth/google/callback — users / residents を find-or-create し、セッション Cookie を発行
authRoute.get('/google/callback', notImplemented)
// POST /auth/logout — セッション破棄
authRoute.post('/logout', notImplemented)
// GET /auth/me — ログイン中の User + Resident を返す
authRoute.get('/me', notImplemented)
