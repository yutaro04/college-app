import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

// 日記（setlog 風の毎日 2 秒）。本人のクリップだけを扱う
export const dailyClipsRoute = new Hono<{ Bindings: Env }>()

// GET /daily-clips?from=&to= — 自分の日記クリップ一覧（日付 yyyy-MM-dd）
dailyClipsRoute.get('/', notImplemented)
// PUT /daily-clips/:date — multipart {file, caption?}。その日のクリップを作成 or 撮り直し（上書き）
dailyClipsRoute.put('/:date', notImplemented)
// DELETE /daily-clips/:date
dailyClipsRoute.delete('/:date', notImplemented)
