import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const inviteWishesRoute = new Hono<{ Bindings: Env }>()

// GET /invite-wishes?q=&residentId= — 「〇〇あったら誘って」一覧
inviteWishesRoute.get('/', notImplemented)
// GET /invite-wishes/invitations — 自分の「誘って」に届いた誘い
inviteWishesRoute.get('/invitations', notImplemented)
// POST /invite-wishes/:id/invitations — {message} で誘う
inviteWishesRoute.post('/:id/invitations', notImplemented)
