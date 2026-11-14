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

## モノレポ構成

```
college-app/
├─ apps/
│  ├─ ios/        iOS アプリ（Swift + SwiftUI）— 実装済み。DDD 4層に再編済み
│  ├─ android/    Android アプリ（Kotlin + Jetpack Compose 想定）— 未着手（空のDDDフォルダのみ）
│  └─ web/        Web アプリ（Next.js PWA 想定）— 未着手（空のDDDフォルダのみ）
└─ services/
   └─ api/        バックエンドAPI（Cloudflare Workers + Hono）— スキーマ・API設計確定、雛形実装済み
```

各層とも `domain/ application/ infrastructure/ presentation/` のDDD4層構成（iOSのみ`Shared/`も追加）。
詳細は各層の README を参照: [`apps/ios/README.md`](apps/ios/README.md) ·
[`apps/android/README.md`](apps/android/README.md) · [`apps/web/README.md`](apps/web/README.md) ·
[`services/api/README.md`](services/api/README.md)

## 決定済み事項（再検討する前に必ず確認。理由も合わせて把握すること）

| 決定 | 理由 |
| --- | --- |
| 新バックエンドは **Cloudflare Workers + Hono + D1 + R2** | Vercel/Supabase構成よりコストが有利。詳細は `services/api/README.md` |
| 認証は **自前セッション認証**（Google OAuth + Cookie、`users`/`sessions`テーブル）。Supabase Authは使わない | D1移行に伴いSupabaseへの依存を切るため |
| マッチングは **属性による検索・絞り込み**のみ。自動マッチングのバッチ処理は行わない | シンプルに実装でき、追加テーブルも不要なため（ユーザー合意済み） |
| 属性（タグ）は **ユーザーが自由に追加できるフリータグ** | 管理者による事前登録の運用負荷を避けるため（ユーザー合意済み） |
| 思い出ビデオの音源は **居住者がアップロードするMP3のみ**。YouTube音声の抽出・埋め込みは**絶対に実装しない** | YouTubeの利用規約違反・著作権侵害リスクがあるため。一度提案したが明確に却下された経緯あり |
| 思い出ビデオの動画合成（クリップ結合+音声ミックス）は **iOS側でAVFoundationによりオンデバイスで行う**。サーバー側（Workers/外部API/自前VPS）では行わない | Cloudflare Workersはffmpeg相当の処理ができない。外部動画合成APIやVPSのコスト・運用を避けるため。Web版はこの機能を持たず、完成動画の再生のみ対応 |
| 既存iOS版（Calendar/ひま/Info/Settings）はSupabase直叩き + 別リポジトリ（`collegeCalendar/frontend`）のNext.js APIに依存したまま。新バックエンドへの移行は別途棚卸しが必要 | 新機能（図鑑等）の開発を優先するため。移行は`services/api/README.md`のTODOに記載 |

## 実装状況

### `apps/ios`（実装済み）

- Supabase（PostgREST/GoTrue）+ 別リポジトリのNext.js APIに依存する既存実装。DDD4層
  （`Domain/ Application/ Infrastructure/ Presentation/` + `Shared/`）に再編済み、ビルド確認済み
- 新機能（図鑑・属性・コヒチャ・写真・動画クリップ・思い出ビデオ）は**未実装**。
  `apps/ios/README.md`の「今後追加予定」セクション参照

### `services/api`（スキーマ確定・雛形実装済み、ビジネスロジックは未実装）

- マイグレーション: `infrastructure/db/migrations/0001_init.sql`（users/sessions/residents/
  attribute_categories/attributes/resident_attributes/coffee_chat_requests）、
  `0002_media.sql`（events/resident_photos/event_video_clips/event_memory_videos）
- Hono雛形: `npm install`済み、`tsc --noEmit`通過確認済み。**実装済みエンドポイントは
  `GET /health` と `GET /attribute-categories` のみ**（D1から読む縦串の参考実装）。
  それ以外は`presentation/routes/`にルーティングのみ存在し、`501 Not Implemented`を返すスタブ
- Cloudflareリソース（D1データベース本体・R2バケット）は**まだ作成されていない**
  （`wrangler.jsonc`の`database_id`はプレースホルダーのまま）。作成にはユーザー自身の
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

Event (最小限。Calendar本体の移行は別途)
  ├─1:N─ EventVideoClip (投稿者, r2_key, duration_ms)
  └─1:N─ EventMemoryVideo (music_r2_key, status, output_r2_key)
```

## 次にやること候補（優先度は未確定、都度ユーザーと相談）

- `services/api`: Cloudflareリソース作成（ユーザー実行）→ 認証・図鑑・属性・コヒチャ等の実装
- `apps/ios`: 図鑑系機能の実装、思い出ビデオのAVFoundation合成の実装
- 既存Next.js API（`/api/events`等）の棚卸しと新バックエンドへの移行計画
- `apps/android` / `apps/web` の技術スタック確定・着手
