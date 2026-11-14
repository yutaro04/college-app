# COLLEGE APP API

> モノレポ内の API（バックエンド）層。全体像は [ルート README](../../README.md) を参照。

**実装着手前（スキーマ・API設計のみ確定）。**

## 技術スタック（確定）

- **実行環境**: Cloudflare Workers
- **フレームワーク**: [Hono](https://hono.dev/)
- **DB**: Cloudflare D1（SQLite 互換）
- **ストレージ**: Cloudflare R2（写真・動画などのバイナリ本体。D1 にはオブジェクトキーだけ持つ）
- **認証**: 自前セッション認証（Google OAuth + Cookie セッション。`users` / `sessions` テーブルで管理。Supabase Auth は使わない）
- フロントエンドは Cloudflare Pages に分離（[`apps/web`](../../apps/web) 側で対応）

Vercel + Supabase 構成からの移行であり、既存の iOS 版（[`apps/ios`](../../apps/ios)）が直接叩いている
Supabase / 別リポジトリの Next.js API とは**別物**。既存機能（Calendar・ひま・Info・Settings）の
移行計画は別途棚卸しする。

## 背景・新機能

アプリの内容を拡張し、「カレッジ生図鑑」機能を追加する。

- 居住者ごとのプロフィール（自己紹介等）
- 趣味・興味・専門分野・大学・会社などの属性（タグ）をユーザーが自由に登録
- 属性で検索・絞り込みできる「図鑑」ページ（＝属性ベースのマッチング）
- カレッジ生同士の 1on1（コーヒーチャット）申請機能
- 顔写真・紙の「カレッジ生図鑑」のスキャン画像・自分に関連する写真の投稿
- イベントごとの短尺（2秒程度）動画クリップの投稿
- 投稿されたクリップを結合し、居住者がアップロードしたMP3音源を使って「思い出ビデオ」を生成
  （**iOS側でAVFoundationによりオンデバイス合成**。詳細は後述）

## ドメインモデル

```
User (認証アイデンティティ)
  └─ 1:1 ─ Resident (カレッジ生プロフィール: display_name, avatar_url, bio)
                │
                │ N:M (resident_attributes)
                ▼
         Attribute (タグ本体: value, normalized_value)
                │
                │ N:1
                ▼
       AttributeCategory (趣味 / 興味 / 専門分野 / 大学 / 会社)

Resident ──(1人が複数申請)──> CoffeeChatRequest <──(1人が複数受信)── Resident
  status: pending / accepted / declined / cancelled
```

テーブル定義: [`infrastructure/db/migrations/0001_init.sql`](infrastructure/db/migrations/0001_init.sql)

設計判断:

- **属性はユーザーが自由に追加できるフリータグ**（`POST /residents/me/attributes` が find-or-create）。
  表記ゆれ（例: 「ML」「ml」）は `attributes.normalized_value` の一意制約で完全一致の重複だけ防ぐ。
  表記ゆれの統合（辞書的な名寄せ）は将来の課題として許容する。
- **マッチングは属性ベースの検索・絞り込み**として実装する（自動マッチングのバッチ処理は行わない）。
  `GET /residents/matches` が「自分と共有属性を持つ人」を共有数順に返すだけで、追加テーブルは不要。
- **コーヒーチャット申請は同一ペアへの pending 重複を DB 制約で防止**
  （`uniq_coffee_chat_pending_pair`）。日程調整など申請後のやり取りは本機能のスコープ外。

### 写真・イベント動画クリップ・思い出ビデオ

```
Resident ──1:N── ResidentPhoto (kind: face / paper_directory / gallery, r2_key)

Event (最小限。Calendar 機能本体の移行は別途)
  ├─1:N─ EventVideoClip (resident_id, r2_key, duration_ms)
  └─1:N─ EventMemoryVideo (生成ジョブ: status, music_r2_key, output_r2_key)
```

テーブル定義: [`infrastructure/db/migrations/0002_media.sql`](infrastructure/db/migrations/0002_media.sql)

設計判断:

- 写真・動画の本体は **R2** に置き、D1 には `r2_key` のみ持つ（D1 にバイナリは持たない）。
- 「紙のカレッジ生図鑑」のスキャン画像も `resident_photos`（`kind = 'paper_directory'`）として同じテーブルで扱う。
- クリップの長さ（2秒）は DB 制約では強制できないため、アップロード時にアプリケーション層でバリデーションする想定。
- `events` は Calendar 機能本体の移行前だが、動画クリップ・思い出ビデオの紐付け先として最小限で先行作成した。

### 思い出ビデオの生成方式: iOSでのオンデバイス合成（決定）

音源は **YouTube からの抽出ではなく、居住者が著作権的に問題ない MP3 をアップロードする方式**
に決定した（YouTube 側の利用規約違反・著作権侵害リスクを避けるため）。
`event_memory_videos.music_r2_key` が必須カラムなのはこのため。

クリップの結合・MP3 との合成は **サーバー側では行わず、iOS アプリ内で AVFoundation
（`AVMutableComposition` + `AVAssetExportSession`）を使ってオンデバイスで実行する。**
これにより Shotstack / Creatomate のような外部動画合成 API や、自前の ffmpeg レンダリングサーバー
（VPS 等）は**不要**になる。API 側の役割は「素材（クリップ・MP3）の配布」と
「完成した動画の受け取り・保存」だけに単純化される。

処理の流れ:

1. 居住者が `POST /events/:eventId/memory-video` で MP3 をアップロードし、ジョブを作成（`pending`）
2. 生成を実行する端末（iOS）が `GET /events/:eventId/memory-video` でクリップ一覧・MP3 の URL を取得
3. 端末側で `AVMutableComposition` によりクリップを連結し `AVMutableAudioMix` で MP3 をミックス、
   `AVAssetExportSession` で書き出し（ジョブは `PATCH` で `processing` に更新し、他端末の二重実行を防ぐ）
4. 完成した動画を `PATCH /events/:eventId/memory-video` でアップロードし、`completed` に更新
   （失敗時は `failed` + エラーメッセージ）

**Web 版はこの生成フローには関与しない**（動画作成ボタンを持たず、完成済みの動画の再生のみ対応する）。
Android で同等機能を作る場合は `Media3 Transformer`（Jetpack）が AVFoundation に相当する。

## API 設計

### 認証

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/auth/google/start` | Google OAuth 開始（リダイレクト） |
| GET | `/auth/google/callback` | コールバック。`users` / `residents` を find-or-create し、セッション Cookie を発行 |
| POST | `/auth/logout` | セッション破棄 |
| GET | `/auth/me` | ログイン中の `User` + `Resident` を返す |

### カレッジ生図鑑（Residents）

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/residents` | 図鑑一覧。`?attributeId=`（複数可・OR）/ `?categoryKey=` / `?q=`（名前検索）/ `?cursor=` でページネーション |
| GET | `/residents/:id` | 詳細（属性一覧込み） |
| PATCH | `/residents/me` | 自分のプロフィール更新（`display_name` / `avatar_url` / `bio`） |
| GET | `/residents/matches` | 要ログイン。自分と共有属性を持つ人を共有数の多い順に返す |

### 属性（Attributes）

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/attribute-categories` | カテゴリ一覧（趣味・興味・専門分野・大学・会社） |
| GET | `/attributes?categoryKey=&q=` | 既存タグの検索・オートコンプリート |
| GET | `/residents/me/attributes` | 自分が持つ属性一覧 |
| POST | `/residents/me/attributes` | `{categoryKey, value}`。既存タグがあれば再利用、なければ新規作成して紐付け |
| DELETE | `/residents/me/attributes/:attributeId` | 自分の属性から削除 |

### コーヒーチャット申請

| Method | Path | 説明 |
| --- | --- | --- |
| POST | `/coffee-chat-requests` | `{recipientId, message?}` で申請作成 |
| GET | `/coffee-chat-requests?box=sent\|received&status=` | 送信 / 受信した申請一覧 |
| PATCH | `/coffee-chat-requests/:id` | `{action: "accept" \| "decline" \| "cancel"}` |

### 写真

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/residents/:id/photos?kind=` | 写真一覧（`face` / `paper_directory` / `gallery`） |
| POST | `/residents/me/photos` | multipart アップロード `{kind, file, caption?}` → R2 に保存し `ResidentPhoto` 作成 |
| DELETE | `/residents/me/photos/:photoId` | 自分の写真を削除 |

### イベント動画クリップ・思い出ビデオ

| Method | Path | 説明 |
| --- | --- | --- |
| POST | `/events/:eventId/clips` | multipart アップロード `{file}`（2秒程度、アプリ側でトリミング前提）→ `EventVideoClip` 作成 |
| GET | `/events/:eventId/clips` | クリップ一覧（合成端末がダウンロードする素材） |
| POST | `/events/:eventId/memory-video` | multipart アップロード `{musicFile}`（MP3）→ R2 に保存しジョブ作成（`pending`） |
| GET | `/events/:eventId/memory-video` | ジョブの状態・クリップ/MP3のURL（合成待ち）・完成動画URL（完成後）を取得 |
| PATCH | `/events/:eventId/memory-video` | 合成端末（iOS）からの状態更新。`{status: "processing"}` で合成開始を宣言（二重実行防止）、`{status: "completed", file}`（multipart）で完成動画をアップロード、`{status: "failed", errorMessage}` で失敗報告 |

## ディレクトリ構成（DDD）

```
api/
├─ domain/           エンティティ・値オブジェクト・リポジトリインターフェースなど、
│                     フレームワークに依存しないビジネスルール
│                     （Resident, Attribute, AttributeCategory, CoffeeChatRequest,
│                      ResidentPhoto, Event, EventVideoClip, EventMemoryVideo 等）
├─ application/       ユースケース（ドメイン層のオーケストレーション）
├─ infrastructure/    D1 アクセス・Google OAuth クライアントなど外部連携の実装
│  └─ db/migrations/  D1 スキーマ定義
└─ presentation/      Hono のルーティング・ハンドラ
   ├─ worker.ts        Workers エントリーポイント（ルート一式を mount）
   ├─ env.ts           Bindings（D1 / R2）の型
   └─ routes/          リソースごとの Hono サブルーター
```

現状、実装済みなのは `GET /health` と `GET /attribute-categories`
（D1 から読む最小の縦串。層のつなぎ方の参考実装）のみ。それ以外のエンドポイントは
ルーティングだけ用意し、`501 Not Implemented` を返すスタブ（`presentation/routes/_notImplemented.ts`）。

## セットアップ

```sh
cd services/api
npm install

# D1 データベースと R2 バケットを作成（Cloudflare アカウントでの認証が必要）
npx wrangler login
npx wrangler d1 create college-app
npx wrangler r2 bucket create college-app-media
```

`wrangler d1 create` の出力に含まれる `database_id` を `wrangler.jsonc` の
`REPLACE_WITH_D1_DATABASE_ID` に差し替える。

```sh
# マイグレーション適用
npm run db:migrate:local   # ローカル（wrangler dev 用）
npm run db:migrate:remote  # 本番 D1

# 開発サーバー起動
npm run dev

# 型チェック
npm run typecheck
```

## TODO

- [x] 技術スタックの確定（Cloudflare Workers + Hono + D1 + R2 + 自前セッション認証）
- [x] カレッジ生図鑑・属性・コーヒーチャット申請のテーブル定義
- [x] 写真・イベント動画クリップのテーブル定義
- [x] 上記機能の API 設計
- [x] 思い出ビデオの音源の扱いを決定（MP3アップロード方式。YouTube音声抽出は行わない）
- [x] 思い出ビデオの合成基盤を決定（外部APIやVPSは使わず、iOSでAVFoundationによるオンデバイス合成）
- [x] Hono プロジェクト雛形の作成（`wrangler.jsonc`, `package.json`, D1/R2 bindings, ルート一式）
- [ ] D1 データベース / R2 バケットの実作成（`wrangler d1 create` / `wrangler r2 bucket create`。要 Cloudflare アカウント認証）
- [ ] 各エンドポイントの実装（現状 `/health` と `/attribute-categories` 以外は 501 スタブ）
- [ ] 自前セッション認証（Google OAuth + Cookie セッション）の実装
- [ ] 既存 Next.js API（`/api/events`, `/api/events/config`, `/api/events/create`,
      `/api/auth/google-token`）の棚卸しと、このAPIへの移植計画
