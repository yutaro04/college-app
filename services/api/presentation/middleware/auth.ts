import { createMiddleware } from 'hono/factory'
import { getCookie } from 'hono/cookie'
import type { Context } from 'hono'
import type { AppEnv } from '../env'
import { D1AuthRepository } from '../../infrastructure/db/authRepository'
import { hashSessionToken } from '../../application/sessionToken'

// Web 版は Cookie、ネイティブアプリは Authorization: Bearer でセッショントークンを送る
export const SESSION_COOKIE = 'college_session'

export function sessionToken(c: Context): string | null {
  const header = c.req.header('Authorization')
  if (header?.startsWith('Bearer ')) return header.slice('Bearer '.length).trim() || null
  return getCookie(c, SESSION_COOKIE) ?? null
}

// 要ログインのルートに付ける。セッションが無い・失効していれば 401
export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
  const token = sessionToken(c)
  const auth = token ? await new D1AuthRepository(c.env.DB).findSession(await hashSessionToken(token)) : null
  if (!auth) return c.json({ error: 'ログインが必要です' }, 401)
  c.set('auth', auth)
  await next()
})
