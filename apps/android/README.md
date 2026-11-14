# COLLEGE APP (Android) — WIP

> モノレポ内の Android アプリ層。全体像は [ルート README](../../README.md) を参照。

**未着手。** [`apps/ios`](../ios) の SwiftUI 実装を参考に、Kotlin + Jetpack Compose（想定）で移植する。
技術スタック・ビルド構成は未確定。

## ディレクトリ構成（DDD）

ドメイン駆動設計に基づき、以下の層で分割する想定。

```
android/
├─ domain/           エンティティ・値オブジェクト・リポジトリインターフェースなど、
│                     フレームワークに依存しないビジネスルール
├─ application/       ユースケース（ドメイン層のオーケストレーション）
├─ infrastructure/    Supabase / API クライアントなど外部連携の実装
└─ presentation/      Compose 画面・ViewModel などの UI 層
```

iOS 版（`apps/ios/CollegeApp/Features`, `Stores`, `Core`）が持つ機能を参照しながら、
同等のユースケース（ログイン、カレンダー、ひま表明、設定など）を上記の層に割り当てて実装していく。

## TODO

- [ ] 技術スタックの確定（Kotlin + Jetpack Compose を想定）
- [ ] プロジェクト雛形の作成（Gradle 構成）
- [ ] 認証（Supabase Auth）の実装
- [ ] iOS 版の画面構成に合わせた機能移植
