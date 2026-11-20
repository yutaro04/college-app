# AGENTS.md

AIエージェント（Claude Code等）がこのリポジトリで作業する際のオリエンテーション用ドキュメント。
各層の詳細は個別の README にあるため、ここでは「全体像」と「すでに決定済みで、再検討不要な事項」をまとめる。

## このファイルの保守（最重要）

**コードやアーキテクチャに変更を加えたら、このファイルも同じコミット/作業の中で更新すること。**

- 新しいディレクトリ・層・技術選定を追加/変更したら「モノレポ構成」「技術スタック」を更新する
- スキーマ（テーブル）やAPIエンドポイントを追加/変更したら「ドメインモデル」「実装状況」を更新する
- 「決定済み事項」に反する変更をする場合は、まずその決定が本当に覆っていいか（ユーザーの明示的な指示があるか）を確認し、
  覆すならここの記述も書き換える。黙って放置して内容を古いままにしないこと
- 古い情報が残っていると、このファイルを読んだ将来のエージェントが誤った前提で作業してしまう。
  更新を怠ることは、コードを壊すのと同程度に有害だと考えること

## サービス概要

SHIMOKITA COLLEGE 向け「COLLEGE APP」。寮生（カレッジ生）向けのコミュニティアプリ。

- 既存機能: カレンダー（イベント一覧・作成）、「ひま」表明と誘い、各種情報、設定
- 新規開発中の機能（通称「カレッジ生図鑑」）: 居住者プロフィール、趣味・興味・専門分野・大学・会社等の
  属性タグ、属性による検索（＝マッチング）、コーヒーチャット（1on1）申請、顔写真・紙の図鑑スキャン画像・
  関連写真の投稿、イベントごとの短尺動画クリップ投稿、クリップ+MP3から作る「思い出ビデオ」
- 日記（setlog 風）: 毎日 2 秒の動画を 1 本撮る「日常」と、イベントごとにみんなで撮る「イベント」を分けて持つ。
  クリップをつなげて思い出ビデオにする
- 交流機能: おすすめの店、気になる（マチアプ風の相互いいね）、「〇〇あったら誘って」、空き時間の登録・閲覧、
  ひま募集（時間指定で人を集める）、匿名文通

## モノレポ構成

```
college-app/
├─ apps/
│  ├─ ios/        iOS アプリ（Swift + SwiftUI）— 実装済み。DDD 4層に再編済み
│  ├─ android/    Android アプリ（Kotlin + Jetpack Compose 想定）— 未着手（空のDDDフォルダのみ）
│  └─ web/        Web アプリ（Next.js PWA 想定）— 未着手（空のDDDフォルダのみ）
└─ services/
   ├─ api/        バックエンドAPI（Cloudflare Workers + Hono）— スキーマ・API設計確定、雛形実装済み
   └─ gas/        共有 Google カレンダーを読み書きする GAS（Apps Script の Web アプリ。手で貼って配備する）
```

各層とも `domain/ application/ infrastructure/ presentation/` のDDD4層構成（iOSのみ`Shared/`も追加）。
詳細は各層の README を参照: [`apps/ios/README.md`](apps/ios/README.md) ·
[`apps/android/README.md`](apps/android/README.md) · [`apps/web/README.md`](apps/web/README.md) ·
[`services/api/README.md`](services/api/README.md)

## 決定済み事項（再検討する前に必ず確認。理由も合わせて把握すること）

| 決定 | 理由 |
| --- | --- |
| 新バックエンドは **Cloudflare Workers + Hono + D1 + R2** | Vercel/Supabase構成よりコストが有利。詳細は `services/api/README.md` |
| **Supabase は廃止済み**（プロジェクトごと削除。データは引き継いでいない）。Supabase に戻す・使う変更はしない | ユーザーが削除した。データは不要との確認済み |
| 認証は **自前セッション認証**（`users`/`sessions`テーブル）。iOS は `Authorization: Bearer`、Web 版は Cookie でセッショントークンを送る | D1移行に伴いSupabaseへの依存を切るため |
| ログインは **hlab.college の Google アカウントのみ**。判定はサーバー（`POST /auth/google`）で Google の `hd` クレームとメールの両方を見る。クライアントの `hd` 指定はヒントにすぎないので頼らない | SHIMOKITA COLLEGE が専用ドメインのアカウントを発行しているため（ユーザーの指示） |
| セッションは **無期限**（`sessions.expires_at` が NULL）。一度ログインしたらログアウトするまでログイン画面を出さない。失効はログアウトか `sessions` の行削除で行う。トークンは DB に SHA-256 ハッシュだけ保存 | ユーザーの指示（一度ログインしたら永遠に残す） |
| iOS は **Google に直接ログイン**（iOS 用 OAuth クライアント・PKCE。client secret なし）し、得た access token を `POST /auth/google` に送る。サーバーは tokeninfo の `aud`（= iOS クライアント ID）と userinfo で検証する。アプリ全体がログイン必須（未ログインならログイン画面だけを出す） | Supabase 廃止に伴い。ユーザーの指示（最初の画面でログインを求める） |
| Google のトークン（calendar.events スコープ）は**端末のキーチェーンだけに置き、サーバーは預からない**。プライベートカレンダーへの投稿時だけ access token を `POST /calendar-events` に添えて送る | サーバーに Google の refresh token と client secret を持たせないため |
| マッチングは **属性による検索・絞り込み**のみ。自動マッチングのバッチ処理は行わない | シンプルに実装でき、追加テーブルも不要なため（ユーザー合意済み） |
| 「気になる」は**本人の操作による相互いいね**（双方 like でマッチ）。片思いの相手は明かさない | マチアプ風の機能要望に応えるため。バッチ処理ではないので上の決定とは矛盾しない |
| 日記は**日常用（`daily_clips`、1人1日1本・本人だけが見る）とイベント用（`event_video_clips`、みんなで撮ってみんなで見る）を分ける** | ユーザーの指示（基本は毎日1本の日記、イベントごとに撮ることもある） |
| イベントの思い出ビデオは音源必須、日常の思い出ビデオは音源任意（無ければクリップの音） | `event_memory_videos.music_r2_key` が NOT NULL の既存設計に合わせたため。日常はサーバーに動画を保存しないので制約なし |
| 匿名文通は**相手の resident id・名前を API レスポンスに絶対に含めない**（ペンネームのみ）。通報窓口を必ず用意する | 匿名性はクライアントでなくサーバーで担保するため。匿名ゆえの嫌がらせ対策 |
| 属性（タグ）は **ユーザーが自由に追加できるフリータグ** | 管理者による事前登録の運用負荷を避けるため（ユーザー合意済み） |
| 思い出ビデオの音源は **居住者がアップロードするMP3のみ**。YouTube音声の抽出・埋め込みは**絶対に実装しない** | YouTubeの利用規約違反・著作権侵害リスクがあるため。一度提案したが明確に却下された経緯あり |
| 思い出ビデオの動画合成（クリップ結合+音声ミックス）は **iOS側でAVFoundationによりオンデバイスで行う**。サーバー側（Workers/外部API/自前VPS）では行わない | Cloudflare Workersはffmpeg相当の処理ができない。外部動画合成APIやVPSのコスト・運用を避けるため。Web版はこの機能を持たず、完成動画の再生のみ対応 |
| 既存機能（いまひま・カレンダー招待・MY EVENT・表示名・イベント一覧・投稿先の選択肢・イベント作成）は**すべて新 API に移した**。別リポジトリ（`collegeCalendar/frontend`）の **Next.js API は使わない** | Next.js 側は Supabase 依存で動かなくなったため。イベント一覧もスプレッドシート廃止に伴い移した |
| **スプレッドシートは使わない**（旧 EventCache は廃止）。共有カレンダーの予定は、新 API の Cron Trigger（15 分ごと）が GAS（`services/gas`）経由で取り、D1 の `calendar_events` に入れる。アプリの一覧は D1 を読むだけ。取得範囲は過去 30 日〜60 日先。**既存の行と突き合わせて差分だけを書く**: 消えた予定は論理削除（`deleted_at`）、新しい予定は追加、内容が変わった予定だけ上書き。丸ごと消して入れ直さない。範囲より古い予定は同期で触らずに残す。予定が変わったときだけ版（`calendar_meta.version`）を進める。**アプリは予定を端末にキャッシュし、版が変わったときだけ読み直す**。読むのは今日から 30 日分ずつ（スクロールで次の 30 日。日記用に過去 30 日） | ユーザーの指示（スプレッドシートは運用しない）。GAS は遅いので一覧表示のたびには呼ばない。過去分は日記の「イベント」用。丸ごと入れ替えていたら 15 分ごと × 約 340 件で書き込みが 1 日 12 万行を超え、D1 無料枠（10 万行/日）に達した |
| 共有カレンダー（000_イベント / 001_ハウス・委員会）と ROOM の**読み書きは GAS に任せる**（スクリプトの持ち主の権限で動く）。新 API ↔ GAS はシークレット（新 API の `GAS_POST_SECRET` = GAS のスクリプト プロパティ `POST_SECRET`）で守る | 寮生全員に共有カレンダーの編集権限を配ったり、サービスアカウントに Workspace 管理者の設定をしたりせずに済むため |

## 実装状況

### `apps/ios`（実装済み）

- カレンダーの予定は `EventsStore` が端末にキャッシュする（`Infrastructure/Persistence/CalendarCacheFile.swift`）。
  起動時はキャッシュを表示し、サーバーには版だけを問い合わせる（15 分以内の再問い合わせはしない。引っ張って更新は除く）。
  最初は今日から 30 日分、カレンダーの一番下までスクロールしたら次の 30 日を読む。日記の「イベント」を開いたら過去 30 日分も読む
- 通信先は新 API（`services/api`）だけ（Next.js API は使わなくなった）。DDD4層
  （`Domain/ Application/ Infrastructure/ Presentation/` + `Shared/`）に再編済み、ビルド確認済み
- **既定は本番モード**（https://college-app-api.whitepenguinmatsuo.workers.dev に繋ぎ、Google ログイン必須）。
- **モックモード（起動引数`-UseMockAPI YES`で有効）**: `Infrastructure/Mock/`の`MockURLProtocol`が
  `services/api` 宛ての通信をすべてアプリ内で横取りし、`MockBackend`（インメモリ。起動ごとに`MockSeed`へ戻る）が
  ダミーJSONを返す。ログインも自動
- 図鑑（一覧・検索・タグ絞り込み・共通点が多い人・個人ページ・自分のタグ/自己紹介編集）とコヒチャ（申請・
  承諾/見送り/取り消し）は**UI + `CollegeAPI`クライアント実装済み**。`CollegeAPI`は`services/api/README.md`の
  API設計どおりのパス・JSON形状（camelCase）で叩くので、API実装後はモックを切るだけで繋がる想定
  （レスポンス形状は`MockBackend.collegeAPI`が事実上の仕様。API実装時はこれに合わせるか、両方直すこと）
- 交流機能（おすすめの店・気になる・誘って・空き時間・ひま募集・匿名文通）も**UI + クライアント実装済み**
  （`CollegeAPI+Social.swift`、モックは`MockBackend+Social.swift`）
- 日記（日常・イベント）も実装済み。2 秒への切り出し（最大 1080p）・思い出ビデオの合成（`Infrastructure/Media/`）は実際に動く。
  **イベントのクリップは新 API（`/events`）に上げて共有**し、動画本体はダウンロードして `Clips/event-cache/` にキャッシュする
  （`EventClipsStore`。カレンダーの予定とは `rowKey` = ID + 日付で対応）。**日常のクリップは `/daily-clips` が未実装のため
  端末内（Application Support/Clips/daily）にだけ保存**している。思い出ビデオは端末で合成して共有シートで渡すだけで、サーバーには上げない。
  モックでは`MockBackend+Events.swift`が他の人のイベントクリップを登録し、アプリが`SampleClipGenerator`でサンプル動画を作る（過去の日記も同様）
- タブ構成: Calendar / ひま（いまひま・募集・空き時間） / 図鑑（みんな・おすすめ店・誘って） /
  交流（コヒチャ・気になる・文通） / 日記（日常・イベント）。Settings（図鑑プロフィール編集・各種情報）は
  日記タブ右上の歯車からシートで開く
- ログイン: 本番モードでは、未ログインならログイン画面だけを出す。Google に直接ログイン
  （`Infrastructure/Auth/GoogleAuth.swift`）→ `POST /auth/google` で新 API のセッショントークンを得てキーチェーンに保存し、
  `CollegeAPI` が全リクエストに Bearer で付ける。新 API が 401 を返したらログイン画面に戻す。
  Google の iOS 用 OAuth クライアント（同意画面は「内部」、Calendar API 有効）は作成済みで、`AppConfig.googleClientID` と
  新 API の `GOOGLE_CLIENT_IDS` に設定済み。`AppConfig.defaultCollegeAPIBaseURL` はデプロイ済みの workers.dev の URL
- 写真（顔写真・紙の図鑑スキャン）は**未実装**

### `services/api`（スキーマ確定・雛形実装済み、ビジネスロジックは未実装）

- マイグレーション: `infrastructure/db/migrations/0001_init.sql`（users/sessions/residents/
  attribute_categories/attributes/resident_attributes/coffee_chat_requests）、
  `0002_media.sql`（events/resident_photos/event_video_clips/event_memory_videos）、
  `0003_social.sql`（resident_recommendations/resident_likes/invite_wishes/invite_wish_invitations/
  resident_free_slots/hima_gatherings/hima_gathering_participants/pen_pal_threads/pen_pal_letters/pen_pal_reports）、
  `0004_daily_clips.sql`（daily_clips、events.calendar_event_id）、
  `0005_hima_calendar.sql`（hima_statuses/hima_invites/invite_groups/created_calendar_events。旧 Supabase から移した既存機能）、
  `0006_calendar_cache.sql`（calendar_events/calendar_meta。旧 EventCache スプレッドシートの置き換え）、
  `0007_calendar_soft_delete.sql`（calendar_events.deleted_at。同期で消えた予定の論理削除）
- Hono雛形: `npm install`済み、`tsc --noEmit`通過確認済み。**実装済みエンドポイントは
  `GET /health`、`GET /attribute-categories`、認証（`POST /auth/google`・`POST /auth/logout`・`GET /auth/me`）、
  `PATCH /residents/me`、いまひま（`/hima-statuses`）、カレンダー招待（`/invite-groups`・`/invite-directory`）、
  カレンダー（`/calendar-events` の一覧・投稿先の選択肢・作成・MY EVENT）、図鑑（`/residents`・`/residents/matches`・
  `/residents/:id`・`/residents/me/attributes`・`/attributes`）、コヒチャ（`/coffee-chat-requests`）、交流機能
  （おすすめの店・気になる・誘って・空き時間・ひま募集・匿名文通）、日記のイベントクリップ（`GET /events`・`POST /events/resolve`・
  `/events/:eventId/clips` の投稿・一覧・本体取得・削除。本体は R2 の `events/<eventId>/clips/<clipId>.mp4`。R2 は公開せず
  Worker が認証してから中継する）。iOS が使うものはすべて実装済み**。
  カレンダーの同期は Cron Trigger（`presentation/scheduled.ts`、15 分ごと）。D1 が空のとき（デプロイ直後）は一覧の初回取得でその場で同期する。
  要ログインのルートには `presentation/middleware/auth.ts` の `requireAuth` を付ける（`c.get('auth')` で residentId が取れる）。
  いずれもローカル D1（`wrangler dev --local`）で正常系・異常系を確認済み（GAS は偽のサーバーで代用）。
  本物の Google アカウントでのログインと、本物の GAS との連携は未確認
  未実装（`501 Not Implemented`のスタブ）は写真・思い出ビデオのジョブ（`/events/:eventId/memory-video`）・
  日記の日常（`/daily-clips`）・Web 版ログインだけ
- D1 データベース（`college-app`、APAC）と R2 バケット（`college-app-media`）は**作成済み**、0001〜0006 のマイグレーションも
  リモートに適用済み（0007 は未適用。`npm run db:migrate:remote` をデプロイより先に実行する）。API は **https://college-app-api.whitepenguinmatsuo.workers.dev にデプロイ済み**（Cron 15 分ごと）。
  GAS のシークレット登録と GAS の差し替えはユーザーが実行中。リソース作成やデプロイにはユーザー自身の
  Cloudflareアカウント認証が必要なため、エージェントは`wrangler login/d1 create/r2 bucket create/deploy`
  を勝手に実行しないこと
- 完全なAPI設計（エンドポイント一覧・ドメインモデル図）は`services/api/README.md`参照

### `apps/android`, `apps/web`（未着手）

- 空のDDDフォルダ + WIP README のみ。技術スタックは想定のみで未確定

## ドメインモデル（新機能部分のみ。既存Calendar等は`apps/ios/README.md`参照）

```
User (認証ID) ─1:1─ Resident (display_name, avatar_url, bio)
                        │
                        ├─N:M(resident_attributes)─ Attribute ─N:1─ AttributeCategory
                        │                             (趣味/興味/専門分野/大学/会社。フリータグ)
                        ├─1:N─ ResidentPhoto (kind: face/paper_directory/gallery)
                        └─(申請/被申請)─ CoffeeChatRequest ─(pending/accepted/declined/cancelled)

Resident ─1:N─ ResidentRecommendation / InviteWish(─1:N─ Invitation) / ResidentFreeSlot
Resident ─N:M─ Resident（ResidentLike: like/pass。双方likeでマッチ）
HimaGathering（主催Resident）─N:M─ Resident（参加者）
PenPalThread（starter/partner + ペンネーム）─1:N─ PenPalLetter, PenPalReport

Resident ─1:N─ DailyClip（clip_date ごとに1本。日記の日常用）

Event (最小限。Calendar本体の移行は別途。calendar_event_id + event_date でカレンダーのイベントと対応)
  ├─1:N─ EventVideoClip (投稿者, r2_key, duration_ms)
  └─1:N─ EventMemoryVideo (music_r2_key, status, output_r2_key)
```

## 次にやること候補（優先度は未確定、都度ユーザーと相談）

- `services/api`: Cloudflareリソース作成（ユーザー実行）→ 認証・図鑑・属性・コヒチャ等の実装
- `apps/ios`: 図鑑系機能の実装、思い出ビデオのAVFoundation合成の実装
- `apps/android` / `apps/web` の技術スタック確定・着手
