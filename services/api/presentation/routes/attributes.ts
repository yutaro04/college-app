import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const attributesRoute = new Hono<{ Bindings: Env }>()

// GET /attributes?categoryKey=&q= — 既存タグの検索・オートコンプリート
attributesRoute.get('/', notImplemented)
