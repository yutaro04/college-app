import {
  EVENT_CLIP_CONTENT_TYPES,
  EVENT_CLIP_MAX_BYTES,
  EVENT_CLIPS_PER_RESIDENT_MAX,
  type Event,
  type EventClipRepository,
  type EventClipView,
  type EventRepository,
  type EventSummary,
  type MediaObject,
  type MediaStorage,
} from '../domain/media'
import { UseCaseError } from './errors'

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const LIST_RANGE_DAYS_MAX = 366

export interface EventClipDeps {
  events: EventRepository
  clips: EventClipRepository
  storage: MediaStorage
}

// GET /events?from=&to= — 範囲内のイベント（D1 に行があるもの）とクリップ数
export async function listEvents(events: EventRepository, from: unknown, to: unknown): Promise<EventSummary[]> {
  if (typeof from !== 'string' || typeof to !== 'string' || !DATE_RE.test(from) || !DATE_RE.test(to)) {
    throw new UseCaseError(400, 'from と to を yyyy-MM-dd で指定してください')
  }
  const days = (Date.parse(to) - Date.parse(from)) / 86_400_000
  if (!(days >= 0 && days <= LIST_RANGE_DAYS_MAX)) throw new UseCaseError(400, '期間が不正です')
  return events.listWithClipCounts(from, to)
}

// POST /events/resolve — カレンダーの予定（ID + 日付）に対応する events 行を find-or-create する。
// まだ行が無いときは、カレンダーのキャッシュに実在する予定に限って作る（タイトルもキャッシュから取る）
export async function resolveEvent(
  events: EventRepository,
  residentId: string,
  body: { calendarEventId?: unknown; eventDate?: unknown }
): Promise<Event> {
  const calendarEventId = typeof body.calendarEventId === 'string' ? body.calendarEventId : ''
  const eventDate = typeof body.eventDate === 'string' ? body.eventDate : ''
  if (!calendarEventId || calendarEventId.length > 1024 || !DATE_RE.test(eventDate)) {
    throw new UseCaseError(400, 'calendarEventId と eventDate（yyyy-MM-dd）を指定してください')
  }
  const existing = await events.findByCalendarEvent(calendarEventId, eventDate)
  if (existing) return existing
  const title = await events.calendarEventTitle(calendarEventId, eventDate)
  if (title === null) throw new UseCaseError(404, 'カレンダーにこのイベントが見つかりません')
  return events.findOrCreateForCalendarEvent(calendarEventId, eventDate, title, residentId)
}

export async function listEventClips(deps: EventClipDeps, eventId: string): Promise<EventClipView[]> {
  await requireEvent(deps.events, eventId)
  return deps.clips.list(eventId)
}

// POST /events/:eventId/clips — 動画を R2 に置いてから行を作る（行の作成に失敗したら R2 からも消す）
export async function uploadEventClip(
  deps: EventClipDeps,
  residentId: string,
  eventId: string,
  input: { file: unknown; durationMs: unknown }
): Promise<EventClipView> {
  await requireEvent(deps.events, eventId)
  const file = input.file
  if (!(file instanceof File) || file.size === 0) throw new UseCaseError(400, '動画ファイル（file）を添えてください')
  if (file.size > EVENT_CLIP_MAX_BYTES) throw new UseCaseError(400, '動画が大きすぎます')
  const contentType = file.type || 'video/mp4'
  if (!EVENT_CLIP_CONTENT_TYPES.includes(contentType)) throw new UseCaseError(400, 'mp4 の動画を送ってください')
  const durationMs = parseDuration(input.durationMs)

  if ((await deps.clips.countByResident(eventId, residentId)) >= EVENT_CLIPS_PER_RESIDENT_MAX) {
    throw new UseCaseError(409, `1 つのイベントに投稿できるのは ${EVENT_CLIPS_PER_RESIDENT_MAX} 本までです`)
  }

  const id = crypto.randomUUID()
  const r2Key = `events/${eventId}/clips/${id}.mp4`
  await deps.storage.put(r2Key, await file.arrayBuffer(), contentType)
  try {
    await deps.clips.create({ id, eventId, residentId, r2Key, durationMs })
  } catch (e) {
    await deps.storage.delete(r2Key).catch(() => {})
    throw e
  }
  return (await deps.clips.find(id))!
}

// GET /events/:eventId/clips/:clipId/file — 動画本体（R2 は非公開なので Worker が中継する）
export async function getEventClipFile(deps: EventClipDeps, eventId: string, clipId: string): Promise<MediaObject> {
  const clip = await deps.clips.findRow(clipId)
  if (!clip || clip.eventId !== eventId) throw new UseCaseError(404, 'クリップが見つかりません')
  const object = await deps.storage.get(clip.r2Key)
  if (!object) throw new UseCaseError(404, 'クリップが見つかりません')
  return object
}

// DELETE /events/:eventId/clips/:clipId — 自分のクリップだけ消せる
export async function deleteEventClip(
  deps: EventClipDeps,
  residentId: string,
  eventId: string,
  clipId: string
): Promise<void> {
  const clip = await deps.clips.findRow(clipId)
  if (!clip || clip.eventId !== eventId) throw new UseCaseError(404, 'クリップが見つかりません')
  if (clip.residentId !== residentId) throw new UseCaseError(403, '自分のクリップだけ削除できます')
  await deps.clips.delete(clipId)
  await deps.storage.delete(clip.r2Key)
}

async function requireEvent(events: EventRepository, eventId: string): Promise<Event> {
  const event = await events.find(eventId)
  if (!event) throw new UseCaseError(404, 'イベントが見つかりません')
  return event
}

function parseDuration(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null
  const n = Number(value)
  if (!Number.isInteger(n) || n <= 0 || n > 60_000) throw new UseCaseError(400, 'durationMs が不正です')
  return n
}
