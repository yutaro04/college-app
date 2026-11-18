import { Hono } from 'hono'
import type { Env } from './env'
import { healthRoute } from './routes/health'
import { authRoute } from './routes/auth'
import { residentsRoute } from './routes/residents'
import { attributeCategoriesRoute } from './routes/attributeCategories'
import { attributesRoute } from './routes/attributes'
import { coffeeChatRequestsRoute } from './routes/coffeeChatRequests'
import { eventsRoute } from './routes/events'
import { recommendationsRoute } from './routes/recommendations'
import { likesRoute } from './routes/likes'
import { inviteWishesRoute } from './routes/inviteWishes'
import { freeSlotsRoute } from './routes/freeSlots'
import { himaGatheringsRoute } from './routes/himaGatherings'
import { penPalsRoute } from './routes/penPals'
import { dailyClipsRoute } from './routes/dailyClips'
import { himaStatusesRoute } from './routes/himaStatuses'
import { inviteDirectoryRoute, inviteGroupsRoute } from './routes/inviteGroups'
import { calendarEventsRoute } from './routes/calendarEvents'
import { scheduled } from './scheduled'

const app = new Hono<{ Bindings: Env }>()

app.route('/health', healthRoute)
app.route('/auth', authRoute)
app.route('/residents', residentsRoute)
app.route('/attribute-categories', attributeCategoriesRoute)
app.route('/attributes', attributesRoute)
app.route('/coffee-chat-requests', coffeeChatRequestsRoute)
app.route('/events', eventsRoute)
app.route('/recommendations', recommendationsRoute)
app.route('/likes', likesRoute)
app.route('/invite-wishes', inviteWishesRoute)
app.route('/free-slots', freeSlotsRoute)
app.route('/hima-gatherings', himaGatheringsRoute)
app.route('/pen-pals', penPalsRoute)
app.route('/daily-clips', dailyClipsRoute)
app.route('/hima-statuses', himaStatusesRoute)
app.route('/invite-groups', inviteGroupsRoute)
app.route('/invite-directory', inviteDirectoryRoute)
app.route('/calendar-events', calendarEventsRoute)

export default {
  fetch: app.fetch,
  scheduled,
} satisfies ExportedHandler<Env>
