import { Hono } from 'hono'
import type { AppEnv } from '../env'
import { requireAuth } from '../middleware/auth'
import { D1InviteGroupRepository } from '../../infrastructure/db/inviteGroupRepository'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// カレンダー招待のグループ（本人だけが見る）。すべて要ログイン
export const inviteGroupsRoute = new Hono<AppEnv>()
inviteGroupsRoute.use('*', requireAuth)

// GET /invite-groups
inviteGroupsRoute.get('/', async (c) => {
  const groups = await new D1InviteGroupRepository(c.env.DB).listByOwner(c.get('auth').residentId)
  return c.json({ groups })
})

// POST /invite-groups — {name, emails}
inviteGroupsRoute.post('/', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { name?: unknown; emails?: unknown }
  const name = typeof body.name === 'string' ? body.name.trim() : ''
  const emails = Array.isArray(body.emails)
    ? [...new Set(body.emails.filter((e): e is string => typeof e === 'string').map((e) => e.trim()))]
    : []
  if (!name || name.length > 40) return c.json({ error: 'グループ名は1〜40文字にしてください' }, 400)
  if (emails.length === 0 || emails.length > 50 || !emails.every((e) => EMAIL_RE.test(e))) {
    return c.json({ error: 'メールアドレスが不正です' }, 400)
  }
  const group = await new D1InviteGroupRepository(c.env.DB).create(c.get('auth').residentId, name, emails)
  return c.json({ group }, 201)
})

// DELETE /invite-groups/:id — 自分のグループだけ消せる
inviteGroupsRoute.delete('/:id', async (c) => {
  const deleted = await new D1InviteGroupRepository(c.env.DB).delete(c.get('auth').residentId, c.req.param('id'))
  return deleted ? c.body(null, 204) : c.json({ error: 'not_found' }, 404)
})

// GET /invite-directory — 招待先の候補（ログインしたことのある居住者の名前とメールアドレス）
export const inviteDirectoryRoute = new Hono<AppEnv>()
inviteDirectoryRoute.get('/', requireAuth, async (c) => {
  const users = await new D1InviteGroupRepository(c.env.DB).directory()
  return c.json({ users })
})
