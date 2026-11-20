import { Hono } from 'hono'
import type { Context } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { notImplemented } from './_notImplemented'
import { UseCaseError } from '../../application/errors'
import {
  deleteEventClip,
  getEventClipFile,
  listEventClips,
  listEvents,
  resolveEvent,
  uploadEventClip,
  type EventClipDeps,
} from '../../application/eventClips'
import { D1EventClipRepository, D1EventRepository } from '../../infrastructure/db/eventRepository'
import { R2MediaStorage } from '../../infrastructure/storage/r2MediaStorage'

export const eventsRoute = new Hono<AppEnv>()
eventsRoute.use('*', requireAuth)

eventsRoute.onError((e, c) => {
  if (e instanceof UseCaseError) return c.json({ error: e.message }, e.status)
  throw e
})

const deps = (c: Context<AppEnv>): EventClipDeps => ({
  events: new D1EventRepository(c.env.DB),
  clips: new D1EventClipRepository(c.env.DB),
  storage: new R2MediaStorage(c.env.MEDIA),
})

// GET /events?from=&to= — 期間内のイベント（クリップの投稿先として作られたもの）とクリップ数
eventsRoute.get('/', async (c) => {
  const events = await listEvents(new D1EventRepository(c.env.DB), c.req.query('from'), c.req.query('to'))
  return c.json({ events })
})

// POST /events/resolve — {calendarEventId, eventDate}。カレンダーのイベントに対応する
// events 行を find-or-create して返す（クリップの投稿先 eventId を得るため）
eventsRoute.post('/resolve', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>
  const event = await resolveEvent(new D1EventRepository(c.env.DB), c.get('auth').residentId, body)
  return c.json({ event })
})

// POST /events/:eventId/clips — multipart {file, durationMs?} を R2 に置いて EventVideoClip 作成
eventsRoute.post('/:eventId/clips', async (c) => {
  const form = await c.req.parseBody().catch(() => {
    throw new UseCaseError(400, 'multipart/form-data で送ってください')
  })
  const clip = await uploadEventClip(deps(c), c.get('auth').residentId, c.req.param('eventId'), {
    file: form.file,
    durationMs: form.durationMs,
  })
  return c.json({ clip }, 201)
})

// GET /events/:eventId/clips — クリップ一覧（みんなの分。古い順）
eventsRoute.get('/:eventId/clips', async (c) => {
  const clips = await listEventClips(deps(c), c.req.param('eventId'))
  return c.json({ clips })
})

// GET /events/:eventId/clips/:clipId/file — 動画本体。中身は変わらないので端末で長くキャッシュしてよい
eventsRoute.get('/:eventId/clips/:clipId/file', async (c) => {
  const object = await getEventClipFile(deps(c), c.req.param('eventId'), c.req.param('clipId'))
  return new Response(object.body, {
    headers: {
      'Content-Type': object.contentType,
      'Content-Length': String(object.size),
      ETag: object.etag,
      'Cache-Control': 'private, max-age=31536000, immutable',
    },
  })
})

// DELETE /events/:eventId/clips/:clipId — 自分のクリップを削除（R2 からも消す）
eventsRoute.delete('/:eventId/clips/:clipId', async (c) => {
  await deleteEventClip(deps(c), c.get('auth').residentId, c.req.param('eventId'), c.req.param('clipId'))
  return c.body(null, 204)
})

// POST /events/:eventId/memory-video — MP3 をアップロードしジョブ作成（pending）
eventsRoute.post('/:eventId/memory-video', notImplemented)
// GET /events/:eventId/memory-video — ジョブ状態・クリップ/MP3/完成動画のURLを取得
eventsRoute.get('/:eventId/memory-video', notImplemented)
// PATCH /events/:eventId/memory-video — 合成端末(iOS)からの状態更新
// {status:"processing"} / {status:"completed", file} / {status:"failed", errorMessage}
eventsRoute.patch('/:eventId/memory-video', notImplemented)
