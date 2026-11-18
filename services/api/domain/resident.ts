export interface Resident {
  id: string
  userId: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
  createdAt: string
  updatedAt: string
}

// API が返す居住者（属性一覧込み）。iOS の `Resident` と同じ形
export interface ResidentProfile {
  id: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
  attributes: { id: string; categoryKey: string; value: string }[]
}

// 申請一覧などに埋め込む最小情報。iOS の `ResidentRef` と同じ形
export interface ResidentRef {
  id: string
  displayName: string
  avatarUrl: string | null
}

// 図鑑の絞り込み。attributeIds は OR（どれか 1 つでも持っている人）
export interface ResidentQuery {
  q: string
  attributeIds: string[]
  categoryKey: string | null
}

// 自分と共有している属性の組（GET /residents/matches）
export interface ResidentMatch {
  resident: ResidentProfile
  sharedAttributes: ResidentProfile['attributes']
}

export interface ResidentRepository {
  search(query: ResidentQuery, limit: number): Promise<ResidentProfile[]>
  // 自分と 1 つ以上属性を共有する人の id と共有属性 id
  findSharingAttributes(residentId: string): Promise<{ residentId: string; attributeIds: string[] }[]>
  findProfiles(ids: string[]): Promise<ResidentProfile[]>
  findProfile(id: string): Promise<ResidentProfile | null>
  // 指定した項目だけ更新する（undefined の項目は変えない）
  updateProfile(id: string, patch: { displayName?: string; bio?: string | null }): Promise<void>
}

export const DISPLAY_NAME_MAX = 40
export const BIO_MAX = 500
export const DIRECTORY_LIMIT = 300
