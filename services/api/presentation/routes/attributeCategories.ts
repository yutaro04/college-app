import { Hono } from 'hono'
import type { Env } from '../env'
import { D1AttributeCategoryRepository } from '../../infrastructure/db/attributeCategoryRepository'
import { listAttributeCategories } from '../../application/listAttributeCategories'

export const attributeCategoriesRoute = new Hono<{ Bindings: Env }>()

// GET /attribute-categories — カテゴリ一覧（趣味・興味・専門分野・大学・会社）
attributeCategoriesRoute.get('/', async (c) => {
  const repo = new D1AttributeCategoryRepository(c.env.DB)
  const categories = await listAttributeCategories(repo)
  return c.json({ categories })
})
