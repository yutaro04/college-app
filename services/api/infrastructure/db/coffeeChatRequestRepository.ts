import type {
  CoffeeChatRequestRepository,
  CoffeeChatRequestStatus,
  CoffeeChatRequestView,
} from '../../domain/coffeeChatRequest'

interface Row {
  id: string
  requester_id: string
  recipient_id: string
  status: CoffeeChatRequestStatus
  message: string | null
  created_at: string
  responded_at: string | null
  requester_name: string
  requester_avatar: string | null
  recipient_name: string
  recipient_avatar: string | null
}

const SELECT = `SELECT q.*, rq.display_name AS requester_name, rq.avatar_url AS requester_avatar,
                       rc.display_name AS recipient_name, rc.avatar_url AS recipient_avatar
                  FROM coffee_chat_requests q
                  JOIN residents rq ON rq.id = q.requester_id
                  JOIN residents rc ON rc.id = q.recipient_id`

function toView(r: Row): CoffeeChatRequestView {
  return {
    id: r.id,
    requesterId: r.requester_id,
    recipientId: r.recipient_id,
    status: r.status,
    message: r.message,
    createdAt: r.created_at,
    respondedAt: r.responded_at,
    requester: { id: r.requester_id, displayName: r.requester_name, avatarUrl: r.requester_avatar },
    recipient: { id: r.recipient_id, displayName: r.recipient_name, avatarUrl: r.recipient_avatar },
  }
}

// created_at / responded_at は ISO 8601（UTC, ミリ秒付き）で入れる（アプリがそのまま日時として読む）
export class D1CoffeeChatRequestRepository implements CoffeeChatRequestRepository {
  constructor(private readonly db: D1Database) {}

  async find(id: string): Promise<CoffeeChatRequestView | null> {
    const row = await this.db.prepare(`${SELECT} WHERE q.id = ?`).bind(id).first<Row>()
    return row ? toView(row) : null
  }

  async list(
    residentId: string,
    box: 'sent' | 'received',
    status: CoffeeChatRequestStatus | null
  ): Promise<CoffeeChatRequestView[]> {
    const column = box === 'sent' ? 'q.requester_id' : 'q.recipient_id'
    const { results } = await this.db
      .prepare(`${SELECT} WHERE ${column} = ? AND (? IS NULL OR q.status = ?) ORDER BY q.created_at DESC LIMIT 200`)
      .bind(residentId, status, status)
      .all<Row>()
    return results.map(toView)
  }

  async hasPendingBetween(a: string, b: string): Promise<boolean> {
    const row = await this.db
      .prepare(
        `SELECT 1 FROM coffee_chat_requests WHERE status = 'pending'
           AND ((requester_id = ? AND recipient_id = ?) OR (requester_id = ? AND recipient_id = ?)) LIMIT 1`
      )
      .bind(a, b, b, a)
      .first()
    return row !== null
  }

  async create(requesterId: string, recipientId: string, message: string | null): Promise<string> {
    const id = crypto.randomUUID()
    await this.db
      .prepare(
        `INSERT INTO coffee_chat_requests (id, requester_id, recipient_id, message, created_at) VALUES (?, ?, ?, ?, ?)`
      )
      .bind(id, requesterId, recipientId, message, new Date().toISOString())
      .run()
    return id
  }

  async transition(id: string, status: CoffeeChatRequestStatus): Promise<boolean> {
    const result = await this.db
      .prepare(`UPDATE coffee_chat_requests SET status = ?, responded_at = ? WHERE id = ? AND status = 'pending'`)
      .bind(status, new Date().toISOString(), id)
      .run()
    return result.meta.changes > 0
  }
}
