import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

// 匿名文通。レスポンスには相手の resident_id / 表示名を絶対に含めないこと
export const penPalsRoute = new Hono<{ Bindings: Env }>()

// GET /pen-pals — 自分のスレッド一覧（myAlias / partnerAlias / 最新の手紙 / 未読数）
penPalsRoute.get('/', notImplemented)
// POST /pen-pals — {body}。ランダムな相手を選んでスレッドを作り、最初の手紙を送る
penPalsRoute.post('/', notImplemented)
// GET /pen-pals/:id/letters — 手紙一覧（取得時に相手からの手紙を既読にする）
penPalsRoute.get('/:id/letters', notImplemented)
// POST /pen-pals/:id/letters — {body} で返事を書く
penPalsRoute.post('/:id/letters', notImplemented)
// PATCH /pen-pals/:id — {action: "close"} で文通を終える
penPalsRoute.patch('/:id', notImplemented)
// POST /pen-pals/:id/report — {reason?} 運営へ通報
penPalsRoute.post('/:id/report', notImplemented)
