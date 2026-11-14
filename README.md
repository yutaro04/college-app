# COLLEGE APP

SHIMOKITA COLLEGE 向け「COLLEGE APP」のモノレポ。
ドメイン駆動設計（DDD）に基づき、クライアントアプリ（iOS / Android / Web）とバックエンド API を
1つのリポジトリで管理する。

## 構成

```
college-app/
├─ apps/
│  ├─ ios/        iOS アプリ（Swift + SwiftUI）— 実装済み
│  ├─ android/    Android アプリ（Kotlin + Jetpack Compose 想定）— WIP
│  └─ web/        Web アプリ（Next.js PWA 想定）— WIP
└─ services/
   └─ api/        バックエンド API — WIP
```

| 層 | パス | 状態 | 詳細 |
| --- | --- | --- | --- |
| iOS アプリ | [`apps/ios`](apps/ios) | 実装済み | [README](apps/ios/README.md) |
| Android アプリ | [`apps/android`](apps/android) | **WIP**（未着手） | [README](apps/android/README.md) |
| Web アプリ | [`apps/web`](apps/web) | **WIP**（未着手。既存実装は別リポジトリ） | [README](apps/web/README.md) |
| API | [`services/api`](services/api) | **WIP**（未着手） | [README](services/api/README.md) |

各層とも、ドメイン駆動設計に沿って以下のような内部構造を志向する（iOS は実際にこの構造へ
再編済み。詳細は各層の README を参照）。

```
domain/           フレームワークに依存しないビジネスルール（エンティティ・値オブジェクト・リポジトリIF）
application/      ユースケース（ドメイン層のオーケストレーション）
infrastructure/   DB・外部 API・フレームワーク依存の実装
presentation/     UI / コントローラなど、外部に公開するインターフェース
```

## 現状のアーキテクチャ

```
┌────────────┐   ┌────────────────┐   ┌────────────────┐
│  iOS (実装済み) │   │ Android (WIP)   │   │ apps/web (WIP)  │
└───┬────┬───┘   └────────────────┘   └────────────────┘
    │    │
    │ 認証・DB │ イベント取得 / 投稿 / Google 連携
    ▼    ▼
┌─────────┐  ┌──────────────────────┐
│ Supabase │  │ Web 版 Next.js /api/*  │  ← 別リポジトリ（既存デプロイ先。apps/web とは別物）
│ (直接)    │  │                       │
└─────────┘  └──────────┬───────────┘
                         │ service_role / GAS secret / Google client secret
                         ▼
              Google Sheets (EventCache) / GAS / Google Calendar

┌──────────────────────┐
│ services/api (WIP)     │  ← 上記サーバーサイド処理をこのモノレポ内に
└──────────────────────┘     集約・置き換えていく予定
```

現状、クライアントアプリ（iOS / 将来の Android・apps/web）は Supabase を直接叩き、
サーバーサイド処理の窓口として別リポジトリの Next.js API を利用している。
`apps/web`・`services/api` の実装が進み次第、この依存を段階的にモノレポ内へ寄せていく。

## 各層のセットアップ

- iOS: [`apps/ios/README.md`](apps/ios/README.md)
- Android: [`apps/android/README.md`](apps/android/README.md)（WIP）
- Web: [`apps/web/README.md`](apps/web/README.md)（WIP）
- API: [`services/api/README.md`](services/api/README.md)（WIP）
