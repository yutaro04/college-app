import { Hono } from 'hono'
import type { Env } from '../env'
import { notImplemented } from './_notImplemented'

export const recommendationsRoute = new Hono<{ Bindings: Env }>()

// GET /recommendations?genre=&q= — みんなのおすすめの店（投稿者つき）
recommendationsRoute.get('/', notImplemented)
