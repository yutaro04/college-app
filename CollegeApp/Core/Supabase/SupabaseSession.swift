import Foundation

/// Supabase GoTrue のトークンレスポンス。
struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    /// Google の refresh_token。Web 版と同じく `/api/auth/google-token` へ送ってサーバーに保存する。
    var providerRefreshToken: String?
    var user: SupabaseUser

    /// 期限の 60 秒前から「期限切れ扱い」にして先回りでリフレッシュする
    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case providerRefreshToken = "provider_refresh_token"
        case user
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        providerRefreshToken = try c.decodeIfPresent(String.self, forKey: .providerRefreshToken)
        user = try c.decode(SupabaseUser.self, forKey: .user)

        // サーバーからは expires_at(UNIX 秒) が来るが、キーチェーンから読み戻すときは Date になる
        if let epoch = try? c.decode(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let date = try? c.decode(Date.self, forKey: .expiresAt) {
            expiresAt = date
        } else {
            let expiresIn = (try? c.decode(Double.self, forKey: .expiresIn)) ?? 3600
            expiresAt = Date().addingTimeInterval(expiresIn)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encode(refreshToken, forKey: .refreshToken)
        try c.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
        try c.encodeIfPresent(providerRefreshToken, forKey: .providerRefreshToken)
        try c.encode(user, forKey: .user)
    }
}

struct SupabaseUser: Codable, Equatable {
    let id: String
    let email: String?
}

enum AuthError: LocalizedError {
    case cancelled
    case domainNotAllowed(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "ログインをキャンセルしました"
        case .domainNotAllowed(let domain): return "\(domain) のアカウントでログインしてください"
        case .server(let message): return message
        }
    }
}
