import { Hono } from 'hono'
import type { Env } from './env'
import { healthRoute } from './routes/health'
import { authRoute } from './routes/auth'
import { residentsRoute } from './routes/residents'
import { attributeCategoriesRoute } from './routes/attributeCategories'
import { attributesRoute } from './routes/attributes'
import { coffeeChatRequestsRoute } from './routes/coffeeChatRequests'
import { eventsRoute } from './routes/events'

const app = new Hono<{ Bindings: Env }>()

app.route('/health', healthRoute)
app.route('/auth', authRoute)
app.route('/residents', residentsRoute)
app.route('/attribute-categories', attributeCategoriesRoute)
app.route('/attributes', attributesRoute)
app.route('/coffee-chat-requests', coffeeChatRequestsRoute)
app.route('/events', eventsRoute)

export default app
