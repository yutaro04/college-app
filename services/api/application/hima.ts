import { HIMA_MAX_DURATION_MS, HIMA_MESSAGE_MAX, type HimaInvite, type HimaRepository, type HimaStatus } from '../domain/hima'
import { UseCaseError } from './errors'

function message(raw: unknown): string {
  const text = typeof raw === 'string' ? raw.trim() : ''
  if (text.length > HIMA_MESSAGE_MAX) throw new UseCaseError(400, `メッセージは${HIMA_MESSAGE_MAX}文字以内にしてください`)
  return text
}

// 「今ひま」を表明する（置き換え）。期限は現在より後・24 時間以内
export function postHimaStatus(
  repo: HimaRepository,
  residentId: string,
  body: { message?: unknown; expiresAt?: unknown },
  now = new Date()
): Promise<HimaStatus> {
  const expires = new Date(typeof body.expiresAt === 'string' ? body.expiresAt : '')
  if (isNaN(expires.getTime()) || expires <= now) throw new UseCaseError(400, '期限が不正です')
  if (expires.getTime() - now.getTime() > HIMA_MAX_DURATION_MS) {
    throw new UseCaseError(400, '期限は24時間以内にしてください')
  }
  return repo.replace(residentId, message(body.message), expires.toISOString(), now.toISOString())
}

// 期限内の表明に「誘う」。自分の表明には誘えない
export async function inviteToHima(
  repo: HimaRepository,
  inviterId: string,
  statusId: string,
  body: { message?: unknown },
  now = new Date()
): Promise<HimaInvite> {
  const status = await repo.findActive(statusId, now.toISOString())
  if (!status) throw new UseCaseError(404, 'この「ひま」はもう終わっています')
  if (status.residentId === inviterId) throw new UseCaseError(400, '自分には誘えません')
  return repo.addInvite(statusId, inviterId, message(body.message), now.toISOString())
}
