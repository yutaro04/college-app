import type { GoogleIdentity, GoogleTokenVerifier } from '../../domain/auth'

interface TokenInfo {
  aud?: string
  sub?: string
}

interface UserInfo {
  sub: string
  email?: string
  email_verified?: boolean
  hd?: string
  name?: string
  picture?: string
}

// access token を Google に問い合わせて検証する。
// tokeninfo で「自アプリの OAuth クライアント向けに発行されたトークンか」（aud）を確認してから、
// userinfo で本人情報（hd クレームを含む）を取る。他アプリ向けのトークンの使い回しを防ぐため aud の確認は必須
export class GoogleOAuthTokenVerifier implements GoogleTokenVerifier {
  constructor(private readonly clientIds: string[]) {}

  async verifyAccessToken(accessToken: string): Promise<GoogleIdentity | null> {
    const infoRes = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?access_token=${encodeURIComponent(accessToken)}`
    )
    if (!infoRes.ok) return null
    const info = (await infoRes.json()) as TokenInfo
    if (!info.aud || !this.clientIds.includes(info.aud)) return null

    const userRes = await fetch('https://openidconnect.googleapis.com/v1/userinfo', {
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    if (!userRes.ok) return null
    const user = (await userRes.json()) as UserInfo
    if (!user.email || user.sub !== info.sub) return null

    return {
      sub: user.sub,
      email: user.email,
      emailVerified: user.email_verified === true,
      hostedDomain: user.hd ?? null,
      name: user.name ?? null,
      picture: user.picture ?? null,
    }
  }
}
