import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const coffeeChatRequestsRoute = new Hono<{ Bindings: Env }>()

// POST /coffee-chat-requests — {recipientId, message?} で申請作成
coffeeChatRequestsRoute.post('/', notImplemented)
// GET /coffee-chat-requests?box=sent|received&status= — 送信/受信した申請一覧
coffeeChatRequestsRoute.get('/', notImplemented)
// PATCH /coffee-chat-requests/:id — {action: "accept" | "decline" | "cancel"}
coffeeChatRequestsRoute.patch('/:id', notImplemented)
