import Foundation

/// ログイン状態。キーチェーンに保存し、ログアウトするまで残す（無期限）
struct AuthSession: Codable, Equatable {
    var user: SessionUser
}

/// ログイン中のユーザー。`id` は新 API（services/api）の resident id
struct SessionUser: Codable, Equatable {
    let id: String
    var email: String?
}

enum AuthError: LocalizedError {
    case cancelled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "ログインをキャンセルしました"
        case .server(let message): return message
        }
    }
}
