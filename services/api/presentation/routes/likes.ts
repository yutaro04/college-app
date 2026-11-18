import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const likesRoute = new Hono<{ Bindings: Env }>()

// GET /likes/discover — まだ振り分けていない人を共通属性の多い順に返す（カード用）
likesRoute.get('/discover', notImplemented)
// GET /likes/matches — 相互に「気になる」した相手（topic つき）
likesRoute.get('/matches', notImplemented)
// GET /likes/received-count — 自分を「気になる」した人数（相手は明かさない）
likesRoute.get('/received-count', notImplemented)
// PUT /likes/:residentId — {kind: "like" | "pass", topic?}。結果としてマッチしたかを返す
likesRoute.put('/:residentId', notImplemented)
