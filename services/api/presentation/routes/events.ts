import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const eventsRoute = new Hono<{ Bindings: Env }>()

// POST /events/resolve — {calendarEventId, title, eventDate}。カレンダーのイベントに対応する
// events 行を find-or-create して返す（クリップの投稿先 eventId を得るため）
eventsRoute.post('/resolve', notImplemented)

// POST /events/:eventId/clips — multipart アップロードして EventVideoClip 作成
eventsRoute.post('/:eventId/clips', notImplemented)
// GET /events/:eventId/clips — クリップ一覧（合成端末がダウンロードする素材）
eventsRoute.get('/:eventId/clips', notImplemented)

// POST /events/:eventId/memory-video — MP3 をアップロードしジョブ作成（pending）
eventsRoute.post('/:eventId/memory-video', notImplemented)
// GET /events/:eventId/memory-video — ジョブ状態・クリップ/MP3/完成動画のURLを取得
eventsRoute.get('/:eventId/memory-video', notImplemented)
// PATCH /events/:eventId/memory-video — 合成端末(iOS)からの状態更新
// {status:"processing"} / {status:"completed", file} / {status:"failed", errorMessage}
eventsRoute.patch('/:eventId/memory-video', notImplemented)
