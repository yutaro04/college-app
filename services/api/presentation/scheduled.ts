import type { Env } from './env'
import { gasGateway } from './routes/calendarEvents'
import { syncCalendar } from '../application/syncCalendar'
import { D1CalendarCacheRepository } from '../infrastructure/db/calendarCacheRepository'

// Cron Trigger（wrangler.jsonc の triggers.crons）。カレンダーの予定を GAS から取り直して D1 に入れる
export async function scheduled(_controller: ScheduledController, env: Env): Promise<void> {
  const gas = gasGateway(env)
  if (!gas) {
    console.warn('calendar sync skipped: GAS_WEBAPP_URL / GAS_POST_SECRET が未設定')
    return
  }
  // 失敗したら例外のまま終わらせる（D1 は前回の内容のまま残り、Cloudflare のダッシュボードに失敗が出る）
  const result = await syncCalendar(gas, new D1CalendarCacheRepository(env.DB))
  console.log('calendar synced', result)
}
