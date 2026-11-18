import type {
  AttributeTag,
  FreeSlot,
  FreeSlotRepository,
  HimaGathering,
  HimaGatheringRepository,
  InviteWish,
  InviteWishRepository,
  LikeMatch,
  LikeRepository,
  NewHimaGathering,
  NewRecommendation,
  Recommendation,
  RecommendationGenre,
  RecommendationRepository,
  ResidentLikeKind,
  ResidentSummary,
  ResidentWithAttributes,
  WishInvitation,
} from '../../domain/social'

// 交流機能（匿名文通以外）の D1 リポジトリ。文通は penPalRepository.ts

// 投稿者などを r.id / r.display_name / r.avatar_url で JOIN して持つ行
interface ResidentColumns {
  resident_id: string
  display_name: string
  avatar_url: string | null
}

function summary(row: ResidentColumns): ResidentSummary {
  return { id: row.resident_id, displayName: row.display_name, avatarUrl: row.avatar_url }
}

// LIKE 検索用。% と _ をエスケープする（ESCAPE '\' と組で使う）
function likePattern(q: string): string {
  return `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`
}

async function changed(stmt: D1PreparedStatement): Promise<boolean> {
  const result = await stmt.run()
  return (result.meta.changes ?? 0) > 0
}

// MARK: - おすすめの店

interface RecommendationRow extends ResidentColumns {
  id: string
  name: string
  genre: RecommendationGenre
  area: string | null
  comment: string | null
  url: string | null
  created_at: string
}

const RECOMMENDATION_COLUMNS = `x.id, x.name, x.genre, x.area, x.comment, x.url, x.created_at,
  r.id AS resident_id, r.display_name, r.avatar_url
  FROM resident_recommendations x JOIN residents r ON r.id = x.resident_id`

function toRecommendation(row: RecommendationRow): Recommendation {
  return {
    id: row.id,
    name: row.name,
    genre: row.genre,
    area: row.area,
    comment: row.comment,
    url: row.url,
    createdAt: row.created_at,
    resident: summary(row),
  }
}

export class D1RecommendationRepository implements RecommendationRepository {
  constructor(private readonly db: D1Database) {}

  async list(filter: { genre?: RecommendationGenre; q?: string }, limit: number): Promise<Recommendation[]> {
    const where: string[] = []
    const values: (string | number)[] = []
    if (filter.genre) {
      where.push('x.genre = ?')
      values.push(filter.genre)
    }
    if (filter.q) {
      const p = likePattern(filter.q)
      where.push(`(x.name LIKE ? ESCAPE '\\' OR x.area LIKE ? ESCAPE '\\' OR x.comment LIKE ? ESCAPE '\\')`)
      values.push(p, p, p)
    }
    const { results } = await this.db
      .prepare(
        `SELECT ${RECOMMENDATION_COLUMNS} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
          ORDER BY x.created_at DESC LIMIT ?`
      )
      .bind(...values, limit)
      .all<RecommendationRow>()
    return results.map(toRecommendation)
  }

  async listByResident(residentId: string): Promise<Recommendation[]> {
    const { results } = await this.db
      .prepare(`SELECT ${RECOMMENDATION_COLUMNS} WHERE x.resident_id = ? ORDER BY x.created_at DESC`)
      .bind(residentId)
      .all<RecommendationRow>()
    return results.map(toRecommendation)
  }

  async create(residentId: string, input: NewRecommendation, now: string): Promise<Recommendation> {
    const id = crypto.randomUUID()
    await this.db
      .prepare(
        `INSERT INTO resident_recommendations (id, resident_id, name, genre, area, comment, url, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(id, residentId, input.name, input.genre, input.area, input.comment, input.url, now)
      .run()
    const row = await this.db.prepare(`SELECT ${RECOMMENDATION_COLUMNS} WHERE x.id = ?`).bind(id).first<RecommendationRow>()
    if (!row) throw new Error('failed to create recommendation')
    return toRecommendation(row)
  }

  delete(residentId: string, id: string): Promise<boolean> {
    return changed(
      this.db.prepare('DELETE FROM resident_recommendations WHERE id = ? AND resident_id = ?').bind(id, residentId)
    )
  }
}

// MARK: - 気になる

interface CandidateRow {
  id: string
  display_name: string
  avatar_url: string | null
  bio: string | null
}

interface CandidateAttributeRow {
  resident_id: string
  id: string
  category_key: string
  value: string
}

interface MatchRow extends ResidentColumns {
  my_topic: string | null
  their_topic: string | null
  matched_at: string
}

export class D1LikeRepository implements LikeRepository {
  constructor(private readonly db: D1Database) {}

  async residentExists(residentId: string): Promise<boolean> {
    const row = await this.db.prepare('SELECT 1 AS ok FROM residents WHERE id = ?').bind(residentId).first()
    return row !== null
  }

  async listUndecided(residentId: string): Promise<ResidentWithAttributes[]> {
    // 自分が like / pass のどちらかを付けた相手は除く
    const undecided = `SELECT r.id FROM residents r
      WHERE r.id != ?1
        AND NOT EXISTS (SELECT 1 FROM resident_likes l WHERE l.from_resident_id = ?1 AND l.to_resident_id = r.id)`
    const [residents, attributes] = await this.db.batch([
      this.db
        .prepare(`SELECT id, display_name, avatar_url, bio FROM residents WHERE id IN (${undecided})`)
        .bind(residentId),
      this.db
        .prepare(
          `SELECT ra.resident_id, a.id, c.key AS category_key, a.value
             FROM resident_attributes ra
             JOIN attributes a ON a.id = ra.attribute_id
             JOIN attribute_categories c ON c.id = a.category_id
            WHERE ra.resident_id IN (${undecided})
            ORDER BY c.sort_order, a.value`
        )
        .bind(residentId),
    ])
    const byResident = new Map<string, AttributeTag[]>()
    for (const a of attributes.results as CandidateAttributeRow[]) {
      const list = byResident.get(a.resident_id) ?? []
      list.push({ id: a.id, categoryKey: a.category_key, value: a.value })
      byResident.set(a.resident_id, list)
    }
    return (residents.results as CandidateRow[]).map((r) => ({
      id: r.id,
      displayName: r.display_name,
      avatarUrl: r.avatar_url,
      bio: r.bio,
      attributes: byResident.get(r.id) ?? [],
    }))
  }

  async myAttributeIds(residentId: string): Promise<string[]> {
    const { results } = await this.db
      .prepare('SELECT attribute_id FROM resident_attributes WHERE resident_id = ?')
      .bind(residentId)
      .all<{ attribute_id: string }>()
    return results.map((r) => r.attribute_id)
  }

  async upsert(from: string, to: string, kind: ResidentLikeKind, topic: string | null, now: string): Promise<boolean> {
    const [, reverse] = await this.db.batch([
      this.db
        .prepare(
          `INSERT INTO resident_likes (from_resident_id, to_resident_id, kind, topic, created_at) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT (from_resident_id, to_resident_id)
           DO UPDATE SET kind = excluded.kind, topic = excluded.topic, created_at = excluded.created_at`
        )
        .bind(from, to, kind, topic, now),
      this.db
        .prepare(
          `SELECT 1 AS ok FROM resident_likes WHERE from_resident_id = ? AND to_resident_id = ? AND kind = 'like'`
        )
        .bind(to, from),
    ])
    return kind === 'like' && reverse.results.length > 0
  }

  async listMatches(residentId: string): Promise<LikeMatch[]> {
    const { results } = await this.db
      .prepare(
        `SELECT r.id AS resident_id, r.display_name, r.avatar_url,
                mine.topic AS my_topic, theirs.topic AS their_topic,
                MAX(mine.created_at, theirs.created_at) AS matched_at
           FROM resident_likes mine
           JOIN resident_likes theirs
             ON theirs.from_resident_id = mine.to_resident_id AND theirs.to_resident_id = mine.from_resident_id
           JOIN residents r ON r.id = mine.to_resident_id
          WHERE mine.from_resident_id = ? AND mine.kind = 'like' AND theirs.kind = 'like'
          ORDER BY matched_at DESC`
      )
      .bind(residentId)
      .all<MatchRow>()
    return results.map((row) => ({
      resident: summary(row),
      myTopic: row.my_topic,
      theirTopic: row.their_topic,
      matchedAt: row.matched_at,
    }))
  }

  async countReceived(residentId: string): Promise<number> {
    const row = await this.db
      .prepare(`SELECT COUNT(*) AS count FROM resident_likes WHERE to_resident_id = ? AND kind = 'like'`)
      .bind(residentId)
      .first<{ count: number }>()
    return row?.count ?? 0
  }
}

// MARK: - 〇〇あったら誘って

interface WishRow extends ResidentColumns {
  id: string
  title: string
  note: string | null
  created_at: string
}

interface WishInvitationRow extends ResidentColumns {
  id: string
  wish_title: string
  message: string
  created_at: string
}

const WISH_COLUMNS = `w.id, w.title, w.note, w.created_at, r.id AS resident_id, r.display_name, r.avatar_url
  FROM invite_wishes w JOIN residents r ON r.id = w.resident_id`

function toWish(row: WishRow): InviteWish {
  return { id: row.id, title: row.title, note: row.note, createdAt: row.created_at, resident: summary(row) }
}

export class D1InviteWishRepository implements InviteWishRepository {
  constructor(private readonly db: D1Database) {}

  async list(filter: { residentId?: string; q?: string }, limit: number): Promise<InviteWish[]> {
    const where: string[] = []
    const values: (string | number)[] = []
    if (filter.residentId) {
      where.push('w.resident_id = ?')
      values.push(filter.residentId)
    }
    if (filter.q) {
      const p = likePattern(filter.q)
      where.push(`(w.title LIKE ? ESCAPE '\\' OR w.note LIKE ? ESCAPE '\\')`)
      values.push(p, p)
    }
    const { results } = await this.db
      .prepare(
        `SELECT ${WISH_COLUMNS} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY w.created_at DESC LIMIT ?`
      )
      .bind(...values, limit)
      .all<WishRow>()
    return results.map(toWish)
  }

  async findOwner(wishId: string): Promise<string | null> {
    const row = await this.db
      .prepare('SELECT resident_id FROM invite_wishes WHERE id = ?')
      .bind(wishId)
      .first<{ resident_id: string }>()
    return row?.resident_id ?? null
  }

  async create(residentId: string, title: string, note: string | null, now: string): Promise<InviteWish> {
    const id = crypto.randomUUID()
    await this.db
      .prepare('INSERT INTO invite_wishes (id, resident_id, title, note, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(id, residentId, title, note, now)
      .run()
    const row = await this.db.prepare(`SELECT ${WISH_COLUMNS} WHERE w.id = ?`).bind(id).first<WishRow>()
    if (!row) throw new Error('failed to create invite wish')
    return toWish(row)
  }

  delete(residentId: string, id: string): Promise<boolean> {
    return changed(this.db.prepare('DELETE FROM invite_wishes WHERE id = ? AND resident_id = ?').bind(id, residentId))
  }

  async addInvitation(wishId: string, inviterId: string, message: string, now: string) {
    const id = crypto.randomUUID()
    await this.db
      .prepare(
        'INSERT INTO invite_wish_invitations (id, wish_id, inviter_resident_id, message, created_at) VALUES (?, ?, ?, ?, ?)'
      )
      .bind(id, wishId, inviterId, message, now)
      .run()
    return { id, createdAt: now }
  }

  async listInvitationsFor(residentId: string, limit: number): Promise<WishInvitation[]> {
    const { results } = await this.db
      .prepare(
        `SELECT i.id, w.title AS wish_title, i.message, i.created_at,
                r.id AS resident_id, r.display_name, r.avatar_url
           FROM invite_wish_invitations i
           JOIN invite_wishes w ON w.id = i.wish_id
           JOIN residents r ON r.id = i.inviter_resident_id
          WHERE w.resident_id = ?
          ORDER BY i.created_at DESC
          LIMIT ?`
      )
      .bind(residentId, limit)
      .all<WishInvitationRow>()
    return results.map((row) => ({
      id: row.id,
      wishTitle: row.wish_title,
      message: row.message,
      createdAt: row.created_at,
      inviter: summary(row),
    }))
  }
}

// MARK: - 空き時間

interface SlotRow extends ResidentColumns {
  id: string
  starts_at: string
  ends_at: string
  note: string | null
}

const SLOT_COLUMNS = `s.id, s.starts_at, s.ends_at, s.note, r.id AS resident_id, r.display_name, r.avatar_url
  FROM resident_free_slots s JOIN residents r ON r.id = s.resident_id`

function toSlot(row: SlotRow, withResident: boolean): FreeSlot {
  const slot: FreeSlot = { id: row.id, startsAt: row.starts_at, endsAt: row.ends_at, note: row.note }
  if (withResident) slot.resident = summary(row)
  return slot
}

export class D1FreeSlotRepository implements FreeSlotRepository {
  constructor(private readonly db: D1Database) {}

  async listByResident(residentId: string, from: string, to: string): Promise<FreeSlot[]> {
    const { results } = await this.db
      .prepare(`SELECT ${SLOT_COLUMNS} WHERE s.resident_id = ? AND s.ends_at > ? AND s.starts_at < ? ORDER BY s.starts_at`)
      .bind(residentId, from, to)
      .all<SlotRow>()
    return results.map((row) => toSlot(row, false))
  }

  async listOverlapping(excludeResidentId: string, from: string, to: string): Promise<FreeSlot[]> {
    const { results } = await this.db
      .prepare(
        `SELECT ${SLOT_COLUMNS} WHERE s.resident_id != ? AND s.ends_at > ? AND s.starts_at < ? ORDER BY s.starts_at LIMIT 500`
      )
      .bind(excludeResidentId, from, to)
      .all<SlotRow>()
    return results.map((row) => toSlot(row, true))
  }

  async listCovering(excludeResidentId: string, from: string, to: string): Promise<FreeSlot[]> {
    const { results } = await this.db
      .prepare(
        `SELECT ${SLOT_COLUMNS} WHERE s.resident_id != ? AND s.starts_at <= ? AND s.ends_at >= ? ORDER BY s.starts_at LIMIT 500`
      )
      .bind(excludeResidentId, from, to)
      .all<SlotRow>()
    return results.map((row) => toSlot(row, true))
  }

  async create(residentId: string, startsAt: string, endsAt: string, note: string | null, now: string): Promise<FreeSlot> {
    const id = crypto.randomUUID()
    await this.db
      .prepare(
        'INSERT INTO resident_free_slots (id, resident_id, starts_at, ends_at, note, created_at) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(id, residentId, startsAt, endsAt, note, now)
      .run()
    return { id, startsAt, endsAt, note }
  }

  delete(residentId: string, id: string): Promise<boolean> {
    return changed(
      this.db.prepare('DELETE FROM resident_free_slots WHERE id = ? AND resident_id = ?').bind(id, residentId)
    )
  }
}

// MARK: - ひま募集

interface GatheringRow extends ResidentColumns {
  id: string
  title: string
  location: string | null
  starts_at: string
  ends_at: string
  capacity: number | null
  note: string | null
}

interface ParticipantRow extends ResidentColumns {
  gathering_id: string
}

const GATHERING_COLUMNS = `g.id, g.title, g.location, g.starts_at, g.ends_at, g.capacity, g.note,
  r.id AS resident_id, r.display_name, r.avatar_url
  FROM hima_gatherings g JOIN residents r ON r.id = g.host_resident_id`

export class D1HimaGatheringRepository implements HimaGatheringRepository {
  constructor(private readonly db: D1Database) {}

  // 募集の行と、その参加者の行（参加順）を組み立てる
  private assemble(rows: GatheringRow[], participants: ParticipantRow[]): HimaGathering[] {
    const byGathering = new Map<string, ResidentSummary[]>()
    for (const p of participants) {
      const list = byGathering.get(p.gathering_id) ?? []
      list.push(summary(p))
      byGathering.set(p.gathering_id, list)
    }
    return rows.map((row) => ({
      id: row.id,
      title: row.title,
      location: row.location,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      capacity: row.capacity,
      note: row.note,
      host: summary(row),
      participants: byGathering.get(row.id) ?? [],
    }))
  }

  private async query(where: string, value: string): Promise<HimaGathering[]> {
    const [gatherings, participants] = await this.db.batch([
      this.db.prepare(`SELECT ${GATHERING_COLUMNS} WHERE ${where} ORDER BY g.starts_at`).bind(value),
      this.db
        .prepare(
          `SELECT p.gathering_id, r.id AS resident_id, r.display_name, r.avatar_url
             FROM hima_gathering_participants p
             JOIN residents r ON r.id = p.resident_id
            WHERE p.gathering_id IN (SELECT g.id FROM hima_gatherings g WHERE ${where})
            ORDER BY p.joined_at`
        )
        .bind(value),
    ])
    return this.assemble(gatherings.results as GatheringRow[], participants.results as ParticipantRow[])
  }

  listUpcoming(now: string): Promise<HimaGathering[]> {
    return this.query('g.cancelled_at IS NULL AND g.ends_at > ?', now)
  }

  async find(id: string): Promise<HimaGathering | null> {
    return (await this.query('g.id = ?', id))[0] ?? null
  }

  async findState(id: string) {
    const row = await this.db
      .prepare('SELECT host_resident_id, ends_at, cancelled_at FROM hima_gatherings WHERE id = ?')
      .bind(id)
      .first<{ host_resident_id: string; ends_at: string; cancelled_at: string | null }>()
    return row ? { hostId: row.host_resident_id, endsAt: row.ends_at, cancelled: row.cancelled_at !== null } : null
  }

  async create(hostId: string, input: NewHimaGathering, now: string): Promise<HimaGathering> {
    const id = crypto.randomUUID()
    await this.db
      .prepare(
        `INSERT INTO hima_gatherings (id, host_resident_id, title, location, starts_at, ends_at, capacity, note, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(id, hostId, input.title, input.location, input.startsAt, input.endsAt, input.capacity, input.note, now)
      .run()
    const gathering = await this.find(id)
    if (!gathering) throw new Error('failed to create hima gathering')
    return gathering
  }

  async cancel(id: string, now: string): Promise<void> {
    await this.db
      .prepare('UPDATE hima_gatherings SET cancelled_at = ? WHERE id = ? AND cancelled_at IS NULL')
      .bind(now, id)
      .run()
  }

  async join(id: string, residentId: string, now: string): Promise<boolean> {
    // 定員の確認と追加を 1 文で行い、同時に参加されても定員を超えないようにする
    const inserted = await changed(
      this.db
        .prepare(
          `INSERT OR IGNORE INTO hima_gathering_participants (gathering_id, resident_id, joined_at)
           SELECT g.id, ?, ? FROM hima_gatherings g
            WHERE g.id = ?
              AND (g.capacity IS NULL
                   OR (SELECT COUNT(*) FROM hima_gathering_participants p WHERE p.gathering_id = g.id) < g.capacity)`
        )
        .bind(residentId, now, id)
    )
    if (inserted) return true
    // 追加されなかったのが「参加済み」なら成功扱い
    const row = await this.db
      .prepare('SELECT 1 AS ok FROM hima_gathering_participants WHERE gathering_id = ? AND resident_id = ?')
      .bind(id, residentId)
      .first()
    return row !== null
  }

  async leave(id: string, residentId: string): Promise<void> {
    await this.db
      .prepare('DELETE FROM hima_gathering_participants WHERE gathering_id = ? AND resident_id = ?')
      .bind(id, residentId)
      .run()
  }
}
