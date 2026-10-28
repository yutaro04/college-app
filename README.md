# COLLEGE APP (iOS)

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

`CollegeApp/Core/AppConfig.swift` の `defaultWebAPIBaseURL` を、Web 版（Next.js）の
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
| Calendar | `Features/Calendar/CalendarScreen.swift` | `Calendar.tsx` / `TabBar.tsx` / `Timeline.tsx` |
| ↑ 注目イベントのカルーセル | `Features/Calendar/FeaturedHeader.swift` | `Header.tsx` |
| ↑ イベントカード | `Features/Calendar/EventRow.swift` | `EventCard.tsx` |
| ↑ イベント追加 | `Features/Calendar/AddEventSheet.swift` + `InviteUserPickerView.swift` | `AddEventModal.tsx` / `InviteUserPicker.tsx` |
| ひま | `Features/Hima/HimaScreen.swift` | `HimaView.tsx` / `AvailabilityView.tsx` |
| 各種情報 | `Features/Info/InfoScreen.swift` | `InfoView.tsx` |
| Settings | `Features/Settings/SettingsScreen.swift` | `SettingsView.tsx` / `ProfileView.tsx` |

---

## ディレクトリ

```
CollegeApp/
├─ CollegeAppApp.swift         @main
├─ Core/
│  ├─ AppConfig.swift          接続先・許可ドメイン・OAuth スコープ
│  ├─ Theme.swift              globals.css のカラートークン
│  ├─ KeychainStore.swift      セッションの保存先
│  ├─ Supabase/
│  │  ├─ SupabaseAuth.swift    PKCE + ASWebAuthenticationSession
│  │  ├─ SupabaseSession.swift
│  │  ├─ PostgREST.swift       `DB.fetch/insert/update/delete`
│  │  └─ AuthStore.swift       useAuth 相当
│  └─ API/WebAPI.swift         Next.js API Route のクライアント
├─ Models/                     CalendarEvent / Profile / Availability
├─ Data/                       collegeInfo・mailingLists・日付ユーティリティ
├─ Stores/                     useEvents / useFavorites / useAvailability 等の移植
└─ Features/                   画面
```

`CollegeApp/` は Xcode 16 以降の **synchronized folder** として参照しているので、
ファイルを追加・削除しても `project.pbxproj` を編集する必要はない。

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
