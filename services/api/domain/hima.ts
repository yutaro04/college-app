// いまひま（「今ひま」の表明）と、それへの「誘う」

export interface ResidentSummary {
  id: string
  displayName: string
  avatarUrl: string | null
}

export interface HimaStatus {
  id: string
  resident: ResidentSummary
  message: string
  expiresAt: string
  createdAt: string
}

export interface HimaInvite {
  id: string
  inviter: ResidentSummary
  message: string
  createdAt: string
}

export interface InviteGroup {
  id: string
  name: string
  emails: string[]
}

export interface DirectoryEntry {
  id: string
  displayName: string
  email: string
}

export interface HimaRepository {
  listActive(now: string): Promise<HimaStatus[]>
  // 既存の表明（と紐づく誘い）を消してから作り直す
  replace(residentId: string, message: string, expiresAt: string, now: string): Promise<HimaStatus>
  clear(residentId: string): Promise<void>
  findActive(statusId: string, now: string): Promise<{ residentId: string } | null>
  addInvite(statusId: string, inviterId: string, message: string, now: string): Promise<HimaInvite>
  listInvitesFor(residentId: string, limit: number): Promise<HimaInvite[]>
}

export interface InviteGroupRepository {
  listByOwner(ownerId: string): Promise<InviteGroup[]>
  create(ownerId: string, name: string, emails: string[]): Promise<InviteGroup>
  delete(ownerId: string, id: string): Promise<boolean>
  // 招待先の候補（ログインしたことのある居住者のメールアドレス）
  directory(): Promise<DirectoryEntry[]>
}

export const HIMA_MESSAGE_MAX = 200
// 表明の期限は最長 24 時間
export const HIMA_MAX_DURATION_MS = 24 * 60 * 60 * 1000
