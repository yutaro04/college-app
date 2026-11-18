import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google に直接ログインする（PKCE + ASWebAuthenticationSession）。
/// iOS 用の OAuth クライアントなので client secret は持たず、トークンの更新も端末だけでできる。
///
/// ここで得た access token は、新 API の `POST /auth/google` に送って本人確認・ドメイン判定してもらう。
/// プライベートカレンダーへの投稿にも使う（calendar.events スコープ）。
enum GoogleAuth {
    struct Tokens: Codable, Equatable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date

        /// 期限の 60 秒前から「期限切れ扱い」にして先回りで更新する
        var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
    }

    private static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    // MARK: - サインイン

    @MainActor
    static func signIn() async throws -> Tokens {
        let verifier = PKCE.makeCodeVerifier()
        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: AppConfig.googleScopes),
            URLQueryItem(name: "code_challenge", value: PKCE.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // 画面上でアカウントを hlab.college に絞るだけのヒント。最終判定はサーバー
            URLQueryItem(name: "hd", value: AppConfig.allowedDomain),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
        ]

        let callbackURL = try await WebAuth.start(url: comps.url!, scheme: AppConfig.googleRedirectScheme)
        let code = try authCode(from: callbackURL)
        return try await token([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": AppConfig.googleRedirectURI,
            "client_id": AppConfig.googleClientID,
        ], keepingRefreshToken: nil)
    }

    /// access token を更新する（refresh token は変わらないので引き継ぐ）
    static func refresh(_ refreshToken: String) async throws -> Tokens {
        try await token([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": AppConfig.googleClientID,
        ], keepingRefreshToken: refreshToken)
    }

    /// アプリへの許可を取り消す（ログアウト時）。失敗しても気にしない
    static func revoke(_ token: String) async {
        var req = URLRequest(url: revokeURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["token": token])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - 内部

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private static func token(_ form: [String: String], keepingRefreshToken: String?) async throws -> Tokens {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(form)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.server(errorMessage(from: data) ?? "Google の認証に失敗しました")
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Tokens(
            accessToken: body.access_token,
            refreshToken: body.refresh_token ?? keepingRefreshToken,
            expiresAt: Date().addingTimeInterval(body.expires_in)
        )
    }

    private static func authCode(from url: URL) throws -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
            return code
        }
        if comps?.queryItems?.first(where: { $0.name == "error" })?.value == "access_denied" {
            throw AuthError.cancelled
        }
        throw AuthError.server("Google の認証に失敗しました")
    }

    /// application/x-www-form-urlencoded。値に含まれる "/" "+" "=" なども確実にエスケープする
    private static func formBody(_ form: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["error_description"] as? String) ?? (json["error"] as? String)
    }
}

// MARK: - PKCE

private enum PKCE {
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationSession ラッパー

@MainActor
private enum WebAuth {
    /// 強参照を保持しないとセッションが即座に破棄されてコールバックが来ない
    private static var retained: (session: ASWebAuthenticationSession, anchor: AnchorProvider)?

    static func start(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let anchor = AnchorProvider()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                retained = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = anchor
            // Google のログイン状態を Safari と共有したいので ephemeral にはしない
            session.prefersEphemeralWebBrowserSession = false
            retained = (session, anchor)

            if !session.start() {
                retained = nil
                continuation.resume(throwing: AuthError.server("ブラウザを開けませんでした"))
            }
        }
    }
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
