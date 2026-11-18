# COLLEGE APP (iOS)

> モノレポ内の iOS アプリ層。全体像は [ルート README](../../README.md) を参照。

SHIMOKITA COLLEGE 向け「COLLEGE APP」の iOS ネイティブ版。
Web 版（Next.js PWA）の `collegeCalendar/frontend` を SwiftUI に移植したもの。

- **言語 / UI**: Swift 5 + SwiftUI（iOS 17.0 以上）
- **外部依存ライブラリ: なし**（SPM / CocoaPods 不要。`open CollegeApp.xcodeproj` してすぐビルドできる）

---

## アーキテクチャ

```
┌────────────────┐
│  iOS (このリポジトリ)   │
└───┬────────────┬───┘
    │            │
    │ 認証・DB     │ イベント取得 / 投稿 / Google 連携
    ▼            ▼
┌─────────┐  ┌──────────────────────┐
│ Supabase │  │ Web 版 Next.js /api/*  │
│ (直接)    │  │ (既存のデプロイ先)        │
└─────────┘  └──────────┬───────────┘
                         │ service_role / GAS secret / Google client secret
                         ▼
              Google Sheets (EventCache) / GAS / Google Calendar
```

**サーバーサイドのシークレットは iOS 側に一切持たない。**
`SUPABASE_SERVICE_ROLE_KEY` / `GAS_POST_SECRET` / `GOOGLE_CLIENT_SECRET` を必要とする処理は
Web 版の API Route をそのまま経由する。アプリに埋め込んでいるのは、Web 版でもブラウザに
配信されている公開値（Supabase URL と anon key）だけ。

| 機能 | 経路 |
| --- | --- |
| ログイン / セッション | Supabase GoTrue を直接（PKCE + `ASWebAuthenticationSession`） |
| プロフィール・ひま・招待グループ | Supabase PostgREST を直接（RLS で保護） |
| イベント一覧 | `GET /api/events` |
| 投稿フォームの設定 | `GET /api/events/config` |
| イベント作成 | `POST /api/events/create` |
| Google refresh_token の保存 | `POST /api/auth/google-token` |

---

## セットアップ

### 1. Web 版のデプロイ先を設定する

`CollegeApp/Infrastructure/Config/AppConfig.swift` の `defaultWebAPIBaseURL` を、Web 版（Next.js）の
実際のデプロイ URL に書き換える。

```swift
static let defaultWebAPIBaseURL = URL(string: "https://<本番のドメイン>")!
```

> 現在はプレースホルダーが入っているので、**ここを直さないとイベント一覧が 404 になる**。

### 2. Supabase にリダイレクト URL を登録する（必須）

ネイティブアプリの OAuth コールバックはカスタム URL スキームで受け取る。
Supabase ダッシュボード > **Authentication > URL Configuration > Redirect URLs** に以下を追加する。

```
collegeapp://auth-callback
```

これを登録しないと、Google ログイン後にアプリへ戻らず Web 版の URL にリダイレクトされる。

### 3. Google Cloud 側

Supabase の Google プロバイダ設定（client ID / secret）を Web 版と共用するため、
**Google Cloud 側の追加設定は不要**。リダイレクト先は Supabase のコールバック URL のままでよい。

### 4. ビルド

```sh
open CollegeApp.xcodeproj
```

署名は自動（`CODE_SIGN_STYLE = Automatic` / `DEVELOPMENT_TEAM = YGG499QVBP`）。
別の Apple Developer アカウントでビルドする場合は、ターゲットの
Signing & Capabilities で Team を差し替える。

### 5. 実機で動かす

```sh
DEVICE=$(xcrun devicectl list devices | awk '/physical/ {print $(NF-2)}')
DD=/tmp/CollegeAppBuild

xcodebuild -project CollegeApp.xcodeproj -scheme CollegeApp \
  -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DD" -allowProvisioningUpdates build

xcrun devicectl device install app --device "$DEVICE" \
  "$DD/Build/Products/Debug-iphoneos/CollegeApp.app"

xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
  college.hlab.CollegeApp
```

Xcode から実行する場合は、デバイスを選んで ⌘R でよい。

---

## モックモード（既定で有効）

バックエンド（`services/api`）が未実装のため、**現状は既定でモックモードで起動する**。
`Infrastructure/Mock/MockURLProtocol.swift` が Supabase / Next.js API / `services/api` 宛ての通信を
すべて横取りし、`MockBackend.swift`（インメモリ）がダミーデータを返す。ログインも自動（`下北 太郎`として）。

- 初期データは `MockSeed.swift`（人物・会社名はすべて架空）。アプリを再起動すると初期状態に戻る
- ひまを表明すると、約 10 秒後に誰かから誘いが届いたことになる（30 秒ポーリングで通知される）
- 実サーバーに繋ぐ: 起動引数 `-UseMockAPI NO`
- 文通で手紙を送ると約 15 秒後に相手から返事が来る。ひま募集を立てると約 10 秒後に誰かが参加する
- 日記: 初回起動時に過去 2 週間分（ところどころ抜け）のサンプル日記を生成する。イベントのクリップも開いたときに
  他の人の分として 3 本生成する（`Infrastructure/Mock/SampleClipGenerator.swift`）
- 最初に開くタブを指定: `-InitialTab calendar|hima|directory|connect|diary`
- タブ内のセグメントも指定できる: `-InitialSegment now|gather|free|people|recommendations|wishes|coffeeChat|likes|penPal|daily|event`

```sh
xcrun simctl launch booted college.hlab.CollegeApp -InitialTab directory
```

---

## 開発時にローカルの Next.js を叩く

API のベース URL は起動引数で上書きできる。

Xcode のスキーム > Run > Arguments > **Arguments Passed On Launch** に追加:

```
-WebAPIBaseURL http://localhost:3000     # シミュレータ
-WebAPIBaseURL http://192.168.x.x:3000   # 実機（Mac の LAN IP）
```

コマンドラインから動かす場合:

```sh
# シミュレータ
xcrun simctl launch booted college.hlab.CollegeApp -WebAPIBaseURL http://localhost:3000

# 実機（Mac と同じ Wi-Fi につないでおく。next dev は -H 0.0.0.0 で起動する）
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
  college.hlab.CollegeApp -WebAPIBaseURL http://192.168.x.x:3000
```

`http://` 通信は `NSAllowsLocalNetworking` でローカルネットワークにのみ許可している（本番の HTTPS には影響しない）。

---

## 画面構成

Web 版のリリース時の構成に合わせている（Laundry / Bathroom は Web 版と同じく未完成のため非搭載）。

| タブ | Swift | 移植元 |
| --- | --- | --- |
| Calendar | `Presentation/Calendar/CalendarScreen.swift` | `Calendar.tsx` / `TabBar.tsx` / `Timeline.tsx` |
| ↑ 注目イベントのカルーセル | `Presentation/Calendar/FeaturedHeader.swift` | `Header.tsx` |
| ↑ イベントカード | `Presentation/Calendar/EventRow.swift` | `EventCard.tsx` |
| ↑ イベント追加 | `Presentation/Calendar/AddEventSheet.swift` + `InviteUserPickerView.swift` | `AddEventModal.tsx` / `InviteUserPicker.tsx` |
| ひま（いまひま） | `Presentation/Hima/HimaScreen.swift` | `HimaView.tsx` / `AvailabilityView.tsx` |
| ↑ 募集・空き時間 | `Presentation/Hima/HimaPlanViews.swift` | （新規） |
| 図鑑（みんな） | `Presentation/Directory/DirectoryScreen.swift` + `ResidentDetailView.swift` | （新規） |
| ↑ おすすめ店・誘って | `Presentation/Directory/CommunityBoardViews.swift` | （新規） |
| 交流（コヒチャ） | `Presentation/Connect/ConnectScreen.swift` | （新規） |
| ↑ 気になる・文通 | `Presentation/Connect/LikesView.swift` / `PenPalViews.swift` | （新規） |
| 日記（日常・イベント） | `Presentation/Diary/DiaryScreen.swift` + `ClipCapture.swift` | （新規。setlog 風） |
| Settings（日記タブの歯車から） | `Presentation/Settings/SettingsScreen.swift` | `SettingsView.tsx` / `ProfileView.tsx` |
| ↑ 図鑑プロフィール編集 | `Presentation/Directory/MyDirectoryProfileView.swift` | （新規） |
| ↑ 各種情報 | `Presentation/Info/InfoScreen.swift` | `InfoView.tsx` |

---

## ディレクトリ（DDD）

ドメイン駆動設計に基づき、ドメイン / アプリケーション / インフラ / プレゼンテーションの
4 層 + 層をまたぐ共有ユーティリティ (`Shared/`) で構成している。

```
CollegeApp/
├─ App/
│  └─ CollegeAppApp.swift          @main（コンポジションルート）
├─ Domain/                          フレームワークに依存しないエンティティ
│  ├─ CalendarEvent.swift
│  ├─ Profile.swift
│  ├─ Availability.swift
│  ├─ Resident.swift                 図鑑の居住者・属性カテゴリ・属性タグ
│  ├─ CoffeeChatRequest.swift
│  ├─ Social.swift                   交流機能のモデル
│  └─ SupabaseSession.swift         セッション / ユーザー / AuthError
├─ Application/                     ユースケース（ドメイン層のオーケストレーション）
│  ├─ AuthStore.swift                useAuth 相当（ログイン・セッション管理）
│  ├─ EventsStore.swift              useEvents 相当
│  ├─ AddEventStore.swift            useAddEvent + 招待ピッカー
│  ├─ AvailabilityStore.swift        useAvailability 相当
│  ├─ FavoritesStore.swift           useFavorites + MY EVENT
│  ├─ DirectoryStore.swift           図鑑（一覧・絞り込み・マッチング・自分のタグ）
│  ├─ CoffeeChatStore.swift          コーヒーチャット申請
│  ├─ ClipStores.swift               日記（日常 DiaryStore / イベント EventClipsStore）
│  └─ SocialStores.swift             おすすめの店・気になる・誘って・空き時間/ひま募集・匿名文通
├─ Infrastructure/                  外部連携・永続化の実装
│  ├─ Config/AppConfig.swift         接続先・許可ドメイン・OAuth スコープ
│  ├─ Network/WebAPI.swift           Next.js API Route のクライアント
│  ├─ Network/CollegeAPI.swift       services/api（Hono）のクライアント（+Social.swift に交流機能）
│  ├─ Mock/                          モックモード（MockURLProtocol / MockBackend / MockSeed / SampleClipGenerator）
│  ├─ Media/                         2 秒クリップの保存・切り出し・思い出ビデオ合成（AVFoundation）
│  ├─ Supabase/
│  │  ├─ SupabaseAuth.swift          PKCE + ASWebAuthenticationSession
│  │  └─ PostgREST.swift             `DB.fetch/insert/update/delete`
│  ├─ Persistence/KeychainStore.swift
│  ├─ Notifications/LocalNotifier.swift  `UNUserNotificationCenter` のラッパー
│  └─ StaticData/                    collegeInfo・mailingLists（固定データ）
├─ Presentation/                    画面（SwiftUI View）
│  ├─ Root/RootView.swift
│  ├─ Calendar/ / Hima/ / Info/ / Login/ / Settings/ / Shared/
│  └─ Theme.swift                    globals.css のカラートークン
└─ Shared/
   └─ DateFormatting.swift          ISODate / DateUtil / EmailValidator 等の汎用ユーティリティ
```

`CollegeApp/` は Xcode 16 以降の **synchronized folder** として参照しているので、
上記のように自由にフォルダを分けても `project.pbxproj` を編集する必要はない
（ファイルの実体がどこにあっても、同一ターゲット内なら `import` なしで参照できる）。

---

## Web 版との差分（意図的なもの）

- **Realtime を使わない**。Web 版は Supabase Realtime + 30 秒ポーリングの二重構成だったが、
  iOS では WebSocket を持ち込まずポーリングに一本化している（新着の検知ロジックは同じ）。
- **通知**は Service Worker ではなく `UNUserNotificationCenter` のローカル通知。
  許可は起動時ではなく「暇を表明した直後」（＝誘いが届きうるタイミング）に求める。
- **イベント通知 / ランドリー通知**は Web 版でもリリース時非表示のため未移植。
- お気に入りは `localStorage` ではなく `UserDefaults`、セッションはキーチェーンに保存。

## 未対応

- プッシュ通知（APNs）。現状はアプリ起動中のポーリングによるローカル通知のみ。
- App Store 用アイコンは Web 版の 192×192 を 1024×1024 に拡大したもの。
  提出前に 1024×1024 の原寸画像に差し替えること。

## 今後追加予定（カレッジ生図鑑・思い出ビデオ）

`services/api`（Cloudflare Workers + D1 + R2）側で設計済みの新機能を iOS 側にも実装する。
詳細な API 設計は [`services/api/README.md`](../../services/api/README.md) を参照。

- ~~カレッジ生図鑑（居住者一覧・プロフィール・属性タグによる検索）~~ → UI実装済み（モックデータで動作）
- ~~コーヒーチャット申請（1on1 のお誘い）~~ → UI実装済み（モックデータで動作）
- 顔写真・紙の図鑑のスキャン画像・関連写真の投稿
- ~~イベントごとの短尺動画クリップの投稿~~ → 日記タブに実装済み（日常用の毎日 2 秒と分けている）。
  アップロード API が未実装のため、現状クリップは端末内にだけ保存される
- **思い出ビデオの生成は iOS 側の責務**（`Infrastructure/Media/MemoryVideoComposer.swift` で実装済み）: `AVMutableComposition` + `AVAssetExportSession` で
  クリップを連結し、居住者がアップロードした MP3 を `AVMutableAudioMix` でミックスして
  オンデバイスで書き出す（サーバー側では合成処理を行わない）。Web 版は完成した動画の再生のみ対応。
