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
  await cache.replaceBefore(to.toISOString(), events, now.toISOString())
  await cache.savePostConfig(config)
  return { events: events.length }
}

// イベント一覧。まだ一度も同期していなければ（デプロイ直後）その場で同期する
export async function listCalendarEvents(
  source: CalendarSource | null,
  cache: CalendarCacheRepository
): Promise<{ events: CalendarEvent[]; lastSync: string }> {
  let lastSync = await cache.lastSync()
  if (!lastSync) {
    if (!source) throw new UseCaseError(500, 'サーバー設定が不足しています (GAS_WEBAPP_URL / GAS_POST_SECRET)')
    await syncCalendar(source, cache).catch((e: unknown) => {
      throw new UseCaseError(502, e instanceof Error ? e.message : 'カレンダーの取得に失敗しました')
    })
    lastSync = (await cache.lastSync()) ?? ''
  }
  return { events: await cache.list(), lastSync }
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
