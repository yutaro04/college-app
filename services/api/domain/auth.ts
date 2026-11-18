import type { User } from './user'

// Google が保証する本人情報（access token を Google に問い合わせて得る）
export interface GoogleIdentity {
  sub: string
  email: string
  emailVerified: boolean
  // Google Workspace のドメイン（hd クレーム）。個人の Gmail では null
  hostedDomain: string | null
  name: string | null
  picture: string | null
}

export interface GoogleTokenVerifier {
  // 自アプリ向けに発行された有効なトークンでなければ null
  verifyAccessToken(accessToken: string): Promise<GoogleIdentity | null>
}

// ログイン中の主体。リクエストごとにセッションから復元する
export interface AuthContext {
  userId: string
  residentId: string
  email: string
}

export interface AuthRepository {
  // google_sub で users / residents を find-or-create する
  findOrCreateByGoogle(identity: GoogleIdentity): Promise<{ user: User; residentId: string }>
  createSession(tokenHash: string, userId: string, expiresAt: string | null): Promise<void>
  findSession(tokenHash: string): Promise<AuthContext | null>
  deleteSession(tokenHash: string): Promise<void>
}

// ドメイン制限。hd クレーム（Workspace 管理下のアカウントであること）とメールアドレスの両方で確認する
export function isAllowedIdentity(identity: GoogleIdentity, allowedDomain: string): boolean {
  const domain = allowedDomain.toLowerCase()
  return (
    identity.emailVerified &&
    identity.hostedDomain?.toLowerCase() === domain &&
    identity.email.toLowerCase().endsWith(`@${domain}`)
  )
}
