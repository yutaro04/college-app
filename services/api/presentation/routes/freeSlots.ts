import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const freeSlotsRoute = new Hono<{ Bindings: Env }>()

// GET /free-slots?from=&to= — 指定時間帯をまるごと空けている人の一覧（ひま募集の相手探し用）
freeSlotsRoute.get('/', notImplemented)
