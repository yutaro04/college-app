import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { notImplemented } from './_notImplemented'
import { requireAuth, sessionToken } from '../middleware/auth'
import { D1AuthRepository } from '../../infrastructure/db/authRepository'
import { D1ResidentRepository } from '../../infrastructure/db/residentRepository'
import { GoogleOAuthTokenVerifier } from '../../infrastructure/google/googleTokenVerifier'
import { SignInError, signInWithGoogle } from '../../application/signInWithGoogle'
import { hashSessionToken } from '../../application/sessionToken'

export const authRoute = new Hono<AppEnv>()

// POST /auth/google — ネイティブアプリ用。{ accessToken }（Google の access token）を検証して
// 無期限のセッショントークンを発行する。許可ドメイン外は 403
authRoute.post('/google', async (c) => {
  const body = await c.req.json<{ accessToken?: string }>().catch(() => null)
  if (!body?.accessToken) return c.json({ error: 'accessToken が必要です' }, 400)

  const auth = new D1AuthRepository(c.env.DB)
  try {
    const { token, residentId, email } = await signInWithGoogle(
      {
        verifier: new GoogleOAuthTokenVerifier(
          c.env.GOOGLE_CLIENT_IDS.split(',').map((id) => id.trim()).filter(Boolean)
        ),
        auth,
        allowedDomain: c.env.ALLOWED_EMAIL_DOMAIN,
      },
      body.accessToken
    )
    const resident = await new D1ResidentRepository(c.env.DB).findProfile(residentId)
    return c.json({ token, email, resident })
  } catch (e) {
    if (e instanceof SignInError) return c.json({ error: e.message }, e.status)
    throw e
  }
})

// GET /auth/google/start, /auth/google/callback — Web 版用（Cookie セッション）。Web 版の着手時に実装する
authRoute.get('/google/start', notImplemented)
authRoute.get('/google/callback', notImplemented)

// POST /auth/logout — このセッションだけを破棄する
authRoute.post('/logout', async (c) => {
  const token = sessionToken(c)
  if (token) await new D1AuthRepository(c.env.DB).deleteSession(await hashSessionToken(token))
  return c.body(null, 204)
})

// GET /auth/me — ログイン中のメールアドレスと Resident を返す
authRoute.get('/me', requireAuth, async (c) => {
  const auth = c.get('auth')
  const resident = await new D1ResidentRepository(c.env.DB).findProfile(auth.residentId)
  if (!resident) return c.json({ error: 'not_found' }, 404)
  return c.json({ email: auth.email, resident })
})
