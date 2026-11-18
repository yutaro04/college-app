import { PEN_NAMES, SOCIAL_LIMITS as L, type PenPalLetter, type PenPalRepository, type PenPalThread } from '../domain/social'
import { UseCaseError } from './errors'
import { optionalText, requiredText } from './social'

// 匿名文通。相手の resident id・名前はこの層より外（API レスポンス）に出さない。
// リポジトリが返す PenPalThread / PenPalLetter は最初から自分視点（ペンネーム・fromMe）だけを持つ

function letterBody(raw: unknown): string {
  return requiredText(raw, L.penPalLetter, '手紙', '手紙を書いてください')
}

// 重ならない 2 つのペンネームをランダムに選ぶ
function pickAliases(): { starter: string; partner: string } {
  const i = Math.floor(Math.random() * PEN_NAMES.length)
  let j = Math.floor(Math.random() * (PEN_NAMES.length - 1))
  if (j >= i) j += 1
  return { starter: PEN_NAMES[i], partner: PEN_NAMES[j] }
}

async function myThread(repo: PenPalRepository, residentId: string, threadId: string): Promise<PenPalThread> {
  const thread = await repo.findThread(residentId, threadId)
  // 他人のスレッドも「存在しない」と同じ扱いにする（存在の有無も漏らさない）
  if (!thread) throw new UseCaseError(404, '見つかりません')
  return thread
}

// 最初の手紙を出す。相手はサーバーがランダムに選ぶ
export async function startPenPal(
  repo: PenPalRepository,
  residentId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<PenPalThread> {
  const text = letterBody(body.body)
  const partnerId = await repo.pickPartner(residentId)
  if (!partnerId) throw new UseCaseError(409, 'いま手紙を受け取れる人がいません')
  const threadId = await repo.start(residentId, partnerId, pickAliases(), text, now.toISOString())
  return myThread(repo, residentId, threadId)
}

export async function readPenPalLetters(
  repo: PenPalRepository,
  residentId: string,
  threadId: string,
  now = new Date()
): Promise<PenPalLetter[]> {
  await myThread(repo, residentId, threadId)
  return repo.readLetters(residentId, threadId, now.toISOString())
}

export async function sendPenPalLetter(
  repo: PenPalRepository,
  residentId: string,
  threadId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<PenPalLetter> {
  const thread = await myThread(repo, residentId, threadId)
  if (thread.closedAt) throw new UseCaseError(409, 'この文通は終了しています')
  return repo.addLetter(residentId, threadId, letterBody(body.body), now.toISOString())
}

// PATCH /pen-pals/:id。いまは {action: "close"}（文通を終える）だけ
export async function updatePenPal(
  repo: PenPalRepository,
  residentId: string,
  threadId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<PenPalThread> {
  if (body.action !== 'close') throw new UseCaseError(400, 'action が不正です')
  const thread = await myThread(repo, residentId, threadId)
  if (!thread.closedAt) await repo.close(threadId, now.toISOString())
  return myThread(repo, residentId, threadId)
}

// 運営へ通報する（運営の確認画面は別途）。通報したスレッドの相手とは今後マッチしない
export async function reportPenPal(
  repo: PenPalRepository,
  residentId: string,
  threadId: string,
  body: Record<string, unknown>,
  now = new Date()
): Promise<void> {
  await myThread(repo, residentId, threadId)
  await repo.report(residentId, threadId, optionalText(body.reason, L.penPalReport, '理由'), now.toISOString())
}
