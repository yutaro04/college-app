import type { Context } from 'hono'

// 設計はあるが未実装のエンドポイント用スタブ。詳細は services/api/README.md の API 設計を参照。
export function notImplemented(c: Context) {
  return c.json({ error: 'not_implemented' }, 501)
}
