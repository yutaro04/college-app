# COLLEGE APP (Web) — WIP

> モノレポ内の Web アプリ層。全体像は [ルート README](../../README.md) を参照。

**未着手。** 技術スタックは未確定（既存の Web 版と同じく Next.js PWA を想定）。

## 背景

SHIMOKITA COLLEGE 向け「COLLEGE APP」の Web 版は、現状 **別リポジトリ**
（`collegeCalendar/frontend`、Next.js PWA）で実装・デプロイされている。
[`apps/ios`](../ios) はこの別リポジトリの API Route（`/api/events` など）に依存している
（詳細は [`apps/ios/README.md`](../ios/README.md) のアーキテクチャ図を参照）。

この `apps/web` は、その Web 版を将来的にこのモノレポへ統合していくための置き場所として用意している。
現時点では既存の別リポジトリのコードは移植しておらず、空の DDD レイヤーのみ。

## ディレクトリ構成（DDD）

```
web/
├─ domain/           エンティティ・値オブジェクト・リポジトリインターフェースなど、
│                     フレームワークに依存しないビジネスルール
├─ application/       ユースケース（ドメイン層のオーケストレーション）
├─ infrastructure/    Supabase / API クライアントなど外部連携の実装
└─ presentation/      ページ・コンポーネントなどの UI 層
```

iOS 版（`apps/ios/CollegeApp/Domain`, `Application`, `Infrastructure`, `Presentation`）が
持つ機能を参照しながら、同等のユースケースを上記の層に割り当てて実装していく想定。

## スコープ外（意図的なもの）

- **思い出ビデオの作成機能は持たない。** クリップ結合・MP3ミックスは iOS 側で
  `AVFoundation` を使ってオンデバイス合成する設計のため（詳細は
  [`services/api/README.md`](../../services/api/README.md) 参照）。Web版は
  `services/api` 実装後、完成済みの動画を再生する画面のみ対応する想定。

## TODO

- [ ] 既存リポジトリ（`collegeCalendar/frontend`）を取り込むか、新規実装するかの判断
- [ ] 技術スタックの確定（Next.js PWA を想定）
- [ ] プロジェクト雛形の作成
- [ ] `services/api`（WIP）が実装され次第、そちらへの依存に切り替え
