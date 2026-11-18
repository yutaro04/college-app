import Foundation

/// アプリ全体の接続先設定。
///
/// Supabase の URL / anon key は Web 版でもブラウザに配信されている公開値（RLS で保護される）なので
/// ここに直接埋め込んでいる。service_role key や GAS のシークレットは **絶対にここに置かない** こと。
/// それらを使う処理（イベント作成・Google カレンダー連携）は Web 版の Next.js API を経由する。
enum AppConfig {
    /// Supabase プロジェクト URL
    static let supabaseURL = URL(string: "https://odpbaufydvbofnwryksy.supabase.co")!

    /// Supabase anon key（公開前提の値）
    static let supabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9kcGJhdWZ5ZHZib2Zud3J5a3N5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYwODM0NTksImV4cCI6MjA5MTY1OTQ1OX0.2MqKVzgvJquzt2r5Nu59fkFlV8tIjxcVt03987e__xQ"

    /// Web 版（Next.js）のデプロイ先。`/api/events` などを叩くために使う。
    ///
    /// 開発中は起動引数で差し替えられる:
    ///   `-WebAPIBaseURL http://localhost:3000`（シミュレータ）
    ///   `-WebAPIBaseURL http://192.168.x.x:3000`（実機。Mac の LAN IP）
    static var webAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "WebAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return defaultWebAPIBaseURL
    }

    /// 本番のデプロイ先。Vercel のドメインに合わせて書き換えること。
    static let defaultWebAPIBaseURL = URL(string: "https://college-calendar-frontend.vercel.app")!

    /// 新バックエンド（`services/api`、Cloudflare Workers + Hono）の接続先。図鑑・コヒチャ等で使う。
    ///
    /// 開発中は起動引数で差し替えられる: `-CollegeAPIBaseURL http://localhost:8787`
    static var collegeAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "CollegeAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return defaultCollegeAPIBaseURL
    }

    /// 本番のデプロイ先（未デプロイのため仮の値。`wrangler dev` の既定ポート）
    static let defaultCollegeAPIBaseURL = URL(string: "http://localhost:8787")!

    /// モックモード。true の間は全ての通信（Supabase / Next.js API / services/api）を
    /// `MockURLProtocol` がアプリ内で横取りしてダミーデータを返し、ログインも自動で済ませる。
    ///
    /// バックエンドが揃うまでは既定で有効。実サーバーに繋ぐときは起動引数 `-UseMockAPI NO` を渡す。
    static var useMockAPI: Bool {
        // 起動引数の値は文字列で入るので、"NO" / "false" も解釈できる bool(forKey:) で読む
        UserDefaults.standard.object(forKey: "UseMockAPI") == nil || UserDefaults.standard.bool(forKey: "UseMockAPI")
    }

    /// ログインを許可するメールドメイン（Web 版・GAS の ALLOWED_DOMAIN と揃える）
    static let allowedDomain = "hlab.college"

    /// OAuth コールバックで使うカスタム URL スキーム。
    /// Supabase ダッシュボード > Authentication > URL Configuration > Redirect URLs に
    /// `collegeapp://auth-callback` を登録しておく必要がある。
    static let authCallbackScheme = "collegeapp"
    static let authCallbackURL = "collegeapp://auth-callback"

    /// Google OAuth で要求するスコープ（Web 版と同じ。プライベートカレンダー投稿用に calendar.events を含む）
    static let googleScopes = "openid email profile https://www.googleapis.com/auth/calendar.events"
}
