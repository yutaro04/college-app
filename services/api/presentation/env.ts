import type { AuthContext } from '../domain/auth'

export interface Env {
  DB: D1Database
  MEDIA: R2Bucket
  // ログインを許可するメールドメイン（wrangler.jsonc の vars）
  ALLOWED_EMAIL_DOMAIN: string
  // Google OAuth クライアント ID（カンマ区切りで複数可）。access token の aud がこのどれかでなければ拒否する
  GOOGLE_CLIENT_IDS: string
  // 共有カレンダーの読み書きを任せる GAS の Web アプリ（`wrangler secret put` で設定する。GAS 側は services/gas）
  GAS_WEBAPP_URL?: string
  GAS_POST_SECRET?: string
}

export type AppEnv = { Bindings: Env; Variables: { auth: AuthContext } }
