import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const himaGatheringsRoute = new Hono<{ Bindings: Env }>()

// GET /hima-gatherings — これからのひま募集（参加者つき）
himaGatheringsRoute.get('/', notImplemented)
// POST /hima-gatherings — {title, location?, startsAt, endsAt, capacity?, note?}
himaGatheringsRoute.post('/', notImplemented)
// DELETE /hima-gatherings/:id — 主催者による取り消し（cancelled_at を立てる）
himaGatheringsRoute.delete('/:id', notImplemented)
// POST /hima-gatherings/:id/join — 参加（定員超過は 409）
himaGatheringsRoute.post('/:id/join', notImplemented)
// DELETE /hima-gatherings/:id/join — 参加取り消し
himaGatheringsRoute.delete('/:id/join', notImplemented)
