import Foundation

/// アプリ全体の接続先設定。
///
/// ここに置くのは公開してよい値だけ。GAS のシークレットなどは **絶対にここに置かない** こと
/// （それを使うイベント作成は新 API がサーバー側で行う）。
enum AppConfig {
    /// バックエンド（`services/api`、Cloudflare Workers + Hono）の接続先。アプリの通信はすべてここに向かう。
    ///
    /// 開発中は起動引数で差し替えられる:
    ///   `-CollegeAPIBaseURL http://localhost:8787`（シミュレータ）
    ///   `-CollegeAPIBaseURL http://192.168.x.x:8787`（実機。Mac の LAN IP）
    static var collegeAPIBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "CollegeAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return defaultCollegeAPIBaseURL
    }

    /// 本番のデプロイ先（Cloudflare Workers の workers.dev）
    static let defaultCollegeAPIBaseURL = URL(string: "https://college-app-api.whitepenguinmatsuo.workers.dev")!

    /// モックモード。true の間は全ての通信（services/api）を
    /// `MockURLProtocol` がアプリ内で横取りしてダミーデータを返し、ログインも自動で済ませる。
    ///
    /// 既定は無効（本番の API に繋ぎ、Google ログインを求める）。ダミーデータで動かすときは起動引数 `-UseMockAPI YES` を渡す。
    static var useMockAPI: Bool {
        // 起動引数の値は文字列で入るので、"YES" / "true" も解釈できる bool(forKey:) で読む
        UserDefaults.standard.bool(forKey: "UseMockAPI")
    }

    /// ログインを許可するメールドメイン。Google のログイン画面の絞り込みに使う（最終判定は新 API の `ALLOWED_EMAIL_DOMAIN`）
    static let allowedDomain = "hlab.college"

    /// Google Cloud の OAuth クライアント ID（種類: iOS、バンドル ID: college.hlab.CollegeApp）。
    /// 作成したら差し替え、新 API の `GOOGLE_CLIENT_IDS` にも同じ値を入れること
    static let googleClientID = "627516720362-2ukviegfp03vf5jbuiu4avob88g48r23.apps.googleusercontent.com"

    /// iOS クライアントのリダイレクト先は「クライアント ID を逆順にしたスキーム」と決まっている
    /// （例: `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`）
    static var googleRedirectScheme: String {
        googleClientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var googleRedirectURI: String { "\(googleRedirectScheme):/oauth2redirect" }

    /// Google OAuth で要求するスコープ（プライベートカレンダー投稿用に calendar.events を含む）
    static let googleScopes = "openid email profile https://www.googleapis.com/auth/calendar.events"
}
