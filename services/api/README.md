# COLLEGE APP API

> モノレポ内の API（バックエンド）層。全体像は [ルート README](../../README.md) を参照。

**実装着手前（スキーマ・API設計のみ確定）。**

## 技術スタック（確定）

- **実行環境**: Cloudflare Workers
- **フレームワーク**: [Hono](https://hono.dev/)
- **DB**: Cloudflare D1（SQLite 互換）
- **ストレージ**: Cloudflare R2（写真・動画などのバイナリ本体。D1 にはオブジェクトキーだけ持つ）
- **認証**: 自前セッション認証（`users` / `sessions` テーブルで管理。Supabase Auth には依存しない）。
  hlab.college の Google アカウントのみ許可し、セッションは無期限。詳細は下の「認証」
- フロントエンドは Cloudflare Pages に分離（[`apps/web`](../../apps/web) 側で対応）

Vercel + Supabase 構成からの移行。**Supabase は廃止済み**（データは引き継いでいない）。
既存機能（いまひま・カレンダー招待・MY EVENT・イベント一覧・イベント作成）はすべてこの API に移した。
別リポジトリの Next.js API とスプレッドシート（EventCache）は使わない。
共有 Google カレンダーの読み書きは GAS（[`services/gas`](../gas)）に任せる。

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
| POST | `/auth/google` | **実装済み**。ネイティブアプリ用。`{ accessToken }`（Google の access token）を検証し、`{ token, email, resident }` を返す。初回は `users` / `residents` を作成（表示名・アイコンは Google のもの）。許可ドメイン外は 403 |
| GET | `/auth/google/start` | Web 版用。Google OAuth 開始（リダイレクト）。未実装 |
| GET | `/auth/google/callback` | Web 版用。コールバックでセッション Cookie（`college_session`）を発行。未実装 |
| POST | `/auth/logout` | **実装済み**。送ってきたセッションだけを破棄（204） |
| GET | `/auth/me` | **実装済み**。ログイン中の `{ email, resident }`（属性込み）を返す |

設計判断:

- セッショントークンは `Authorization: Bearer <token>`（iOS）か Cookie `college_session`（Web）で送る。
  要ログインのルートは `presentation/middleware/auth.ts` の `requireAuth` を通し、`c.get('auth')` で `userId` / `residentId` を得る
- **ドメイン制限はサーバーで行う**。Google の `hd` クレームが `ALLOWED_EMAIL_DOMAIN`（`hlab.college`）と一致し、
  メールが確認済みで同ドメインであること。ログイン URL の `hd` パラメータは画面の絞り込みにすぎず、改ざんできるので頼らない
- access token は tokeninfo で `aud` が `GOOGLE_CLIENT_IDS` のどれかであることを確かめてから userinfo を読む
  （他アプリ向けに発行されたトークンを持ち込まれるのを防ぐ）
- **セッションは無期限**（`expires_at` が NULL）。トークンは 32 バイトの乱数で、DB には SHA-256 ハッシュだけを保存する。
  失効させるには `/auth/logout`、または管理者が `sessions` の行を消す（退寮者などはユーザーごとに
  `DELETE FROM sessions WHERE user_id = ?`）
- iOS は Google に直接ログイン（iOS 用 OAuth クライアント・PKCE）し、得た access token をここに送る。
  そのため `GOOGLE_CLIENT_IDS` には **iOS 用 OAuth クライアント ID** を入れる（Web 版を作るときは Web 用の ID をカンマ区切りで追加）

### カレッジ生図鑑（Residents）

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/residents` | 図鑑一覧。`?attributeId=`（複数可・OR）/ `?categoryKey=` / `?q=`（名前検索）/ `?cursor=` でページネーション |
| GET | `/residents/:id` | 詳細（属性一覧込み） |
| PATCH | `/residents/me` | **実装済み**。自分のプロフィール更新 `{ displayName?, bio? }`（表示名は 1〜40 文字、自己紹介は 500 文字まで） |
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

### 日記（setlog 風の 2 秒クリップ）

テーブル定義: [`infrastructure/db/migrations/0004_daily_clips.sql`](infrastructure/db/migrations/0004_daily_clips.sql)

クリップは日常用とイベント用の 2 種類に分ける。

| | 日常（`daily_clips`） | イベント（`event_video_clips`） |
| --- | --- | --- |
| 単位 | 1 人 1 日 1 本（撮り直しは上書き） | 1 イベントに何本でも、誰でも |
| 見える人 | 本人だけ | みんな |
| 思い出ビデオ | 期間を選んで本人の端末で合成（サーバーに保存しない。音源は任意） | `event_memory_videos` の流れ（音源 MP3 必須） |

- カレンダーのイベントは Google カレンダー由来で D1 の `events` に行が無いので、
  `POST /events/resolve` で `calendar_event_id + event_date` から find-or-create してから `/events/:id/clips` に投稿する
- 長さ 2 秒はアプリ側で切り出してからアップロードする（DB では強制しない）

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/daily-clips?from=&to=` | 自分の日記クリップ一覧 |
| PUT | `/daily-clips/:date` | multipart `{file, caption?}`。その日のクリップを作成 or 上書き |
| DELETE | `/daily-clips/:date` | |
| POST | `/events/resolve` | `{calendarEventId, title, eventDate}` → `{event}`（find-or-create） |

### 交流機能

テーブル定義: [`infrastructure/db/migrations/0003_social.sql`](infrastructure/db/migrations/0003_social.sql)

```
Resident ──1:N── ResidentRecommendation（おすすめの店。genre: cafe/restaurant/bar/shop/other）
Resident ──N:M── Resident  ResidentLike（kind: like/pass, topic。双方 like でマッチ）
Resident ──1:N── InviteWish（〇〇あったら誘って）──1:N── InviteWishInvitation
Resident ──1:N── ResidentFreeSlot（空き時間）
Resident ──1:N── HimaGathering（ひま募集）──N:M── Resident（hima_gathering_participants）
PenPalThread（starter/partner + それぞれのペンネーム）──1:N── PenPalLetter
                                                      └─1:N── PenPalReport（通報）
```

設計判断:

- **気になる（マチアプ風）は相互いいね**。1 ペア 1 行（`resident_likes` の PK）で、両方向が `like` のときだけ
  マッチとして相手を返す。片思いの相手は返さず、`/likes/received-count` で人数だけ見せる。
  「マッチングは属性検索のみ・自動マッチングのバッチは行わない」という決定とは別物（本人の操作だけで成立し、バッチ処理はない）。
  候補の並び順は共通属性数（`/residents/matches` と同じ考え方）
- **空き時間は本人が手で登録する**（`resident_free_slots`）。Google カレンダーの free/busy から自動生成する場合も
  このテーブルに書く想定（未実装）
- **いま暇の「表明」（`hima_statuses`）と、時間指定で人を集める `hima_gatherings` は別物**。
  表明は「今ひま」を期限付きで出すだけ（1人1件・置き換え）。`hima_gatherings` は「この時間空いてるから誰か〇〇しよう」
- **匿名文通の匿名性はサーバーで守る**。手紙を出すとサーバーが相手をランダムに選び、ペンネームを振る。
  レスポンスには `myAlias` / `partnerAlias` だけを返し、相手の resident id・表示名は**絶対に返さない**。
  嫌がらせ対策として「文通を終える」と運営への通報（`pen_pal_reports`）を用意（運営側の確認画面は別途）

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/recommendations?genre=` | みんなのおすすめの店（投稿者つき） |
| GET | `/residents/:id/recommendations` | その人のおすすめの店 |
| POST | `/residents/me/recommendations` | `{name, genre, area?, comment?, url?}` |
| DELETE | `/residents/me/recommendations/:id` | |
| GET | `/likes/discover` | まだ振り分けていない人（共通点の多い順。カード用） |
| PUT | `/likes/:residentId` | `{kind: "like" \| "pass", topic?}` → `{matched}` |
| GET | `/likes/matches` | マッチした相手（お互いの topic つき） |
| GET | `/likes/received-count` | 自分を気になっている人数 |
| GET | `/invite-wishes?residentId=` | 「〇〇あったら誘って」一覧 |
| POST | `/residents/me/invite-wishes` | `{title, note?}` |
| DELETE | `/residents/me/invite-wishes/:id` | |
| POST | `/invite-wishes/:id/invitations` | `{message}` で誘う |
| GET | `/invite-wishes/invitations` | 自分の「誘って」に届いた誘い |
| GET | `/residents/:id/free-slots` | その人の空き時間（今日から 7 日間） |
| GET | `/free-slots?from=&to=` | 指定時間帯をまるごと空けている人。期間省略時は全員の 7 日分 |
| POST | `/residents/me/free-slots` | `{startsAt, endsAt, note?}` |
| DELETE | `/residents/me/free-slots/:id` | |
| GET | `/hima-gatherings` | これからのひま募集（主催者・参加者つき） |
| POST | `/hima-gatherings` | `{title, location?, startsAt, endsAt, capacity?, note?}` |
| DELETE | `/hima-gatherings/:id` | 主催者が取り消す |
| POST / DELETE | `/hima-gatherings/:id/join` | 参加 / 参加取り消し（定員超過は 409） |
| GET | `/pen-pals` | 自分の文通一覧（ペンネーム・最新の手紙・未読数） |
| POST | `/pen-pals` | `{body}` ランダムな相手に最初の手紙を出す |
| GET | `/pen-pals/:id/letters` | 手紙一覧（取得時に既読化） |
| POST | `/pen-pals/:id/letters` | `{body}` 返事を書く |
| PATCH | `/pen-pals/:id` | `{action: "close"}` 文通を終える |
| POST | `/pen-pals/:id/report` | `{reason?}` 運営へ通報 |

レスポンスの JSON 形状は iOS のモック（`apps/ios/CollegeApp/Infrastructure/Mock/MockBackend+Social.swift`）が
事実上の仕様になっている。実装時はそれに合わせること。

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

iOS アプリが使うエンドポイントはすべて実装済み（認証・図鑑・属性・コヒチャ・交流機能・既存機能）。
**未実装（`501 Not Implemented` のスタブ。`presentation/routes/_notImplemented.ts`）は、写真（`/residents/:id/photos`・
`/residents/me/photos`）・イベント動画（`/events/*`）・日記（`/daily-clips`）・Web 版ログイン（`/auth/google/start`・`/callback`）**。
iOS の日記はクリップを端末内にだけ保存しているので、これらが無くても動く。

実装済みの部分の、モックとの意図的な違い（iOS は影響を受けない）:
- 他人のもの・存在しないものの削除は 404（モックは黙って 200）。削除の成功は 204
- 入力の検証がモックより厳しい（文字数上限、おすすめの店の URL は http(s) のみ、空き時間は最大 7 日・ひま募集は最大 24 時間、
  定員は 1〜100 など）
- 文通の相手選びでは、今文通中の人に加え、通報があった文通の相手（どちらが通報したかは問わない）も選ばない（嫌がらせ対策）
- 一覧には上限がある（図鑑 300 人、気になるの候補 50 人など）

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

### 既存機能（旧 Supabase / Next.js から移したもの）

テーブル定義: [`0005_hima_calendar.sql`](infrastructure/db/migrations/0005_hima_calendar.sql)・
[`0006_calendar_cache.sql`](infrastructure/db/migrations/0006_calendar_cache.sql)。
すべて**実装済み**・要ログイン。

| Method | Path | 説明 |
| --- | --- | --- |
| GET | `/hima-statuses` | 期限内の「今ひま」表明（新しい順） |
| PUT | `/hima-statuses/me` | `{ message, expiresAt }` 表明する。既存の表明とそれへの誘いは消える。期限は 24 時間以内 |
| DELETE | `/hima-statuses/me` | 表明を取り下げる |
| GET | `/hima-statuses/me/invites` | 自分の表明に届いた誘い（新しい順・最大 50 件。アプリは 30 秒ごとにポーリング） |
| POST | `/hima-statuses/:id/invites` | `{ message }` 誘う。期限切れは 404、自分の表明には 400 |
| GET | `/invite-directory` | カレンダー招待の候補（ログインしたことのある居住者の名前とメールアドレス） |
| GET / POST | `/invite-groups` | 自分の招待グループ一覧 / `{ name, emails }` で作成 |
| DELETE | `/invite-groups/:id` | 自分のグループだけ消せる（他人のものは 404） |
| GET | `/calendar-events` | 共有カレンダーの予定 `{ events, lastSync }`（過去 30 日〜60 日先・開始日時順）。D1 のキャッシュを返す。一度も同期していなければその場で同期する |
| GET | `/calendar-events/config` | 投稿先カレンダーと ROOM の選択肢 `{ config: { calendars, rooms } }`（末尾に「プライベート」を足す） |
| POST | `/calendar-events` | Google カレンダーにイベントを作る（入力の検証規則は旧 Next.js と同じ）。`event` / `house` は GAS の Web アプリ経由（`GAS_WEBAPP_URL` / `GAS_POST_SECRET` が必要）。`private` は本文の `googleAccessToken`（アプリが持つ本人のトークン）で本人の primary カレンダーに直接作る。共有カレンダーに作った予定はその場で D1 にも入れる（次の同期を待たずに一覧に出る） |
| GET | `/calendar-events/mine` | 自分が作ったイベントの ID（Calendar の MY EVENT 用） |

設計判断:

- **サーバーは Google の refresh token を預からない**（旧構成の `google_oauth_tokens` は廃止）。
  プライベートカレンダーへの投稿は、アプリが端末に持つ本人の access token をその都度受け取って使う
- **カレンダーの予定は D1 にキャッシュする**（旧 EventCache スプレッドシートの置き換え）。Cron Trigger
  （`wrangler.jsonc` の `triggers.crons`、15 分ごと。`presentation/scheduled.ts`）が GAS から過去 30 日〜60 日先の予定を取り、
  `calendar_events` の「開始が範囲の終わりより前」の行を丸ごと入れ替える（カレンダーから消えた予定も消える）。
  同期に失敗しても D1 は前回の内容のまま（batch は 1 トランザクション）。GAS は 1 回数秒かかるので一覧表示のたびには呼ばない
- 繰り返し予定は回ごとに同じイベント ID で現れるので、`calendar_events` の主キーは `(event_id, start_iso)`
- GAS のシークレットは `wrangler secret put GAS_WEBAPP_URL` / `wrangler secret put GAS_POST_SECRET` で設定する。
  `GAS_POST_SECRET` は GAS のスクリプト プロパティ `POST_SECRET` と同じ値
- ローカルで同期を試すとき: `wrangler dev --test-scheduled` で起動し、`curl localhost:8787/__scheduled`

## TODO

- [x] 技術スタックの確定（Cloudflare Workers + Hono + D1 + R2 + 自前セッション認証）
- [x] カレッジ生図鑑・属性・コーヒーチャット申請のテーブル定義
- [x] 写真・イベント動画クリップのテーブル定義
- [x] 上記機能の API 設計
- [x] 思い出ビデオの音源の扱いを決定（MP3アップロード方式。YouTube音声抽出は行わない）
- [x] 思い出ビデオの合成基盤を決定（外部APIやVPSは使わず、iOSでAVFoundationによるオンデバイス合成）
- [x] Hono プロジェクト雛形の作成（`wrangler.jsonc`, `package.json`, D1/R2 bindings, ルート一式）
- [x] 交流機能（おすすめの店・気になる・誘って・空き時間・ひま募集・匿名文通）のテーブル定義・API 設計・ルートのスタブ
- [x] 日記（日常用 daily_clips / イベント用との分離）のテーブル定義・API 設計・スタブ
- [x] D1 データベースの実作成
- [x] R2 バケットの実作成
- [x] デプロイ（https://college-app-api.whitepenguinmatsuo.workers.dev。マイグレーション 0001〜0006 適用済み）
- [ ] GAS のシークレット登録（`GAS_WEBAPP_URL` / `GAS_POST_SECRET`）と GAS（`services/gas`）の差し替え
- [x] 図鑑・属性・コヒチャ・交流機能のエンドポイントの実装
- [ ] 写真・イベント動画・日記のアップロード（R2）のエンドポイントの実装
- [x] 自前セッション認証（ネイティブアプリ用 `POST /auth/google`・ログアウト・`/auth/me`・`requireAuth`）
- [ ] Web 版用の Cookie ログイン（`/auth/google/start`・`/auth/google/callback`）
- [x] 旧 Supabase の既存機能（いまひま・招待グループ・MY EVENT）と、Next.js の `/api/events*` の移植
- [x] スプレッドシートの廃止（予定は Cron で GAS から取って D1 にキャッシュ）
