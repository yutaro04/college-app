import { isAllowedIdentity, type AuthRepository, type GoogleTokenVerifier } from '../domain/auth'
import { generateSessionToken, hashSessionToken } from './sessionToken'

export class SignInError extends Error {
  constructor(
    readonly status: 401 | 403,
    message: string
  ) {
    super(message)
  }
}

// Google の access token を検証し、許可ドメインのアカウントなら無期限のセッションを発行する
export async function signInWithGoogle(
  deps: { verifier: GoogleTokenVerifier; auth: AuthRepository; allowedDomain: string },
  accessToken: string
): Promise<{ token: string; residentId: string; email: string }> {
  const identity = await deps.verifier.verifyAccessToken(accessToken)
  if (!identity) throw new SignInError(401, 'Google の認証に失敗しました')
  if (!isAllowedIdentity(identity, deps.allowedDomain)) {
    throw new SignInError(403, `${deps.allowedDomain} のアカウントでログインしてください`)
  }

  const { user, residentId } = await deps.auth.findOrCreateByGoogle(identity)
  const token = generateSessionToken()
  await deps.auth.createSession(await hashSessionToken(token), user.id, null)
  return { token, residentId, email: user.email }
}
