import type { MediaObject, MediaStorage } from '../../domain/media'

// 写真・動画の本体を置く R2 バケット（wrangler.jsonc の MEDIA）。公開せず、Worker が認証してから中継する
export class R2MediaStorage implements MediaStorage {
  constructor(private readonly bucket: R2Bucket) {}

  async put(key: string, body: ArrayBuffer | ReadableStream, contentType: string): Promise<void> {
    await this.bucket.put(key, body, { httpMetadata: { contentType } })
  }

  async get(key: string): Promise<MediaObject | null> {
    const object = await this.bucket.get(key)
    if (!object) return null
    return {
      body: object.body,
      size: object.size,
      contentType: object.httpMetadata?.contentType ?? 'application/octet-stream',
      etag: object.httpEtag,
    }
  }

  async delete(key: string): Promise<void> {
    await this.bucket.delete(key)
  }
}
