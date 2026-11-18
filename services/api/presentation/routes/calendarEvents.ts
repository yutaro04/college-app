import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { createCalendarEvent, parseCreateCalendarEventInput } from '../../application/createCalendarEvent'
import { UseCaseError } from '../../application/errors'
import { GasCalendarGateway } from '../../infrastructure/calendar/gasCalendarGateway'
import { GooglePrivateCalendarGateway } from '../../infrastructure/calendar/googlePrivateCalendarGateway'
import { D1CreatedCalendarEventRepository } from '../../infrastructure/db/createdCalendarEventRepository'
import { D1CalendarCacheRepository } from '../../infrastructure/db/calendarCacheRepository'
import { getPostConfig, listCalendarEvents } from '../../application/syncCalendar'
import type { Env } from '../env'

// Google カレンダー（旧 Next.js の /api/events・/api/events/config・/api/events/create）。
// 一覧は Cron Trigger が GAS から取って D1 に入れたものを返す（presentation/scheduled.ts）
export const calendarEventsRoute = new Hono<AppEnv>()

export function gasGateway(env: Env): GasCalendarGateway | null {
  return env.GAS_WEBAPP_URL && env.GAS_POST_SECRET ? new GasCalendarGateway(env.GAS_WEBAPP_URL, env.GAS_POST_SECRET) : null
}
calendarEventsRoute.use('*', requireAuth)

calendarEventsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

// GET /calendar-events — 共有カレンダーの予定（過去 30 日〜60 日先。開始日時順）
calendarEventsRoute.get('/', async (c) => {
  return c.json(await listCalendarEvents(gasGateway(c.env), new D1CalendarCacheRepository(c.env.DB)))
})

// GET /calendar-events/config — 投稿先カレンダーと ROOM の選択肢（末尾に「プライベート」を足す）
calendarEventsRoute.get('/config', async (c) => {
  const config = await getPostConfig(gasGateway(c.env), new D1CalendarCacheRepository(c.env.DB))
  return c.json({ config })
})

// POST /calendar-events — CreateCalendarEventInput + googleAccessToken（calendarKey が private のときだけ必須）
calendarEventsRoute.post('/', async (c) => {
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null
  if (!body) return c.json({ error: 'リクエストが不正です' }, 400)
  const input = parseCreateCalendarEventInput(body)
  const event = await createCalendarEvent(
    {
      shared: gasGateway(c.env),
      private: new GooglePrivateCalendarGateway(),
      created: new D1CreatedCalendarEventRepository(c.env.DB),
      cache: new D1CalendarCacheRepository(c.env.DB),
    },
    c.get('auth').residentId,
    input,
    typeof body.googleAccessToken === 'string' ? body.googleAccessToken : null
  )
  return c.json({ event }, 201)
})

// GET /calendar-events/mine — 自分が作ったイベントの ID（MY EVENT 用）
calendarEventsRoute.get('/mine', async (c) => {
  const eventIds = await new D1CreatedCalendarEventRepository(c.env.DB).listIds(c.get('auth').residentId)
  return c.json({ eventIds })
})
