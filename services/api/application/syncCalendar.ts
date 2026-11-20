import type { CalendarCacheRepository, CalendarEvent, CalendarSource, PostConfig } from '../domain/calendar'
import { UseCaseError } from './errors'

const DAY_MS = 24 * 60 * 60 * 1000
// 同期する範囲。過去分は日記の「イベント」でクリップを付けるために持つ
export const SYNC_PAST_DAYS = 30
export const SYNC_FUTURE_DAYS = 60

// 「プライベート」は GAS を介さず本人の Google カレンダーに作るので、GAS の選択肢とは別にここで足す
const PRIVATE_OPTION = { key: 'private', name: 'プライベート' }

// GAS から予定と投稿先の選択肢を取り直して D1 に入れる（Cron Trigger から 15 分ごとに呼ばれる）
export async function syncCalendar(source: CalendarSource, cache: CalendarCacheRepository, now = new Date()) {
  const from = new Date(now.getTime() - SYNC_PAST_DAYS * DAY_MS)
  const to = new Date(now.getTime() + SYNC_FUTURE_DAYS * DAY_MS)
  const [events, config] = await Promise.all([source.fetchEvents(from, to), source.fetchPostConfig()])
  // 範囲より先の予定（範囲外に作られたもの）は、範囲に入ってから同期で整える
  await cache.syncRange(from.toISOString(), to.toISOString(), events, now.toISOString())
  await cache.savePostConfig(config)
  return { events: events.length }
}

// 一覧で一度に頼める日数（アプリは 30 日ずつ読む）
const LIST_DAYS_MAX = 62
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

export type CalendarEventsResult =
  | { notModified: true; version: string }
  | { notModified: false; version: string; events: CalendarEvent[]; hasMore: boolean }

// イベント一覧。from / to は日本時間の日付（yyyy-MM-dd、両端を含む）。省略時は同期範囲全体（過去 30 日〜60 日先）。
// アプリが手元のキャッシュの版（version）を送ってきて、それが今の版と同じなら予定は読まずに notModified を返す
// （D1 の読み込みは版の 1 行だけで済む）。まだ一度も同期していなければ（デプロイ直後）その場で同期する
export async function listCalendarEvents(
  source: CalendarSource | null,
  cache: CalendarCacheRepository,
  query: { from?: string; to?: string; version?: string },
  now = new Date()
): Promise<CalendarEventsResult> {
  let version = await cache.version()
  if (!version) {
    if (!source) throw new UseCaseError(500, 'サーバー設定が不足しています (GAS_WEBAPP_URL / GAS_POST_SECRET)')
    await syncCalendar(source, cache, now).catch((e: unknown) => {
      throw new UseCaseError(502, e instanceof Error ? e.message : 'カレンダーの取得に失敗しました')
    })
    version = (await cache.version()) ?? now.toISOString()
  }
  if (query.version && query.version === version) return { notModified: true, version }

  const syncEnd = now.getTime() + SYNC_FUTURE_DAYS * DAY_MS
  let from: number
  let to: number
  if (query.from === undefined && query.to === undefined) {
    from = now.getTime() - SYNC_PAST_DAYS * DAY_MS
    to = syncEnd
  } else {
    if (!query.from || !query.to || !DATE_RE.test(query.from) || !DATE_RE.test(query.to)) {
      throw new UseCaseError(400, 'from と to を yyyy-MM-dd で指定してください')
    }
    from = Date.parse(`${query.from}T00:00:00+09:00`)
    to = Date.parse(`${query.to}T00:00:00+09:00`) + DAY_MS // to の日の終わりまで
    const days = (to - from) / DAY_MS
    if (!(days >= 1 && days <= LIST_DAYS_MAX)) throw new UseCaseError(400, '期間が不正です')
  }
  const events = await cache.list(new Date(from).toISOString(), new Date(to).toISOString())
  // 同期しているのは 60 日先まで。それより先を頼まれても空なので、アプリに読み進めるのをやめてもらう
  return { notModified: false, version, events, hasMore: to < syncEnd }
}

export async function getPostConfig(source: CalendarSource | null, cache: CalendarCacheRepository): Promise<PostConfig> {
  let config = await cache.loadPostConfig()
  if (!config) {
    if (!source) throw new UseCaseError(500, 'サーバー設定が不足しています (GAS_WEBAPP_URL / GAS_POST_SECRET)')
    config = await source.fetchPostConfig().catch((e: unknown) => {
      throw new UseCaseError(502, e instanceof Error ? e.message : '設定の取得に失敗しました')
    })
    await cache.savePostConfig(config)
  }
  return { ...config, calendars: [...config.calendars.filter((c) => c.key !== PRIVATE_OPTION.key), PRIVATE_OPTION] }
}
