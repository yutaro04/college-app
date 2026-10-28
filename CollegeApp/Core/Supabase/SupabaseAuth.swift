import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Supabase GoTrue を URLSession だけで叩く薄いクライアント。
/// ネイティブアプリなので OAuth は PKCE フロー + ASWebAuthenticationSession を使う。
enum SupabaseAuth {
    private static var authBase: URL { AppConfig.supabaseURL.appendingPathComponent("auth/v1") }

    // MARK: - Google サインイン

    /// Google OAuth をブラウザで実行し、取得したセッションを返す。
    @MainActor
    static func signInWithGoogle() async throws -> SupabaseSession {
        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)

        var comps = URLComponents(url: authBase.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: AppConfig.authCallbackURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            URLQueryItem(name: "scopes", value: AppConfig.googleScopes),
            // Web 版と同じ: ドメイン絞り込み + refresh_token を確実に受け取るための指定
            URLQueryItem(name: "hd", value: AppConfig.allowedDomain),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let callbackURL = try await WebAuth.start(url: comps.url!, scheme: AppConfig.authCallbackScheme)
        let code = try authCode(from: callbackURL)
        let session = try await exchange(code: code, verifier: verifier)

        guard isAllowed(email: session.user.email) else {
            // 許可外ドメインのセッションはサーバー側にも残さない
            try? await signOut(accessToken: session.accessToken)
            throw AuthError.domainNotAllowed(AppConfig.allowedDomain)
        }
        return session
    }

    static func isAllowed(email: String?) -> Bool {
        guard let email else { return false }
        return email.lowercased().hasSuffix("@\(AppConfig.allowedDomain)")
    }

    private static func authCode(from url: URL) throws -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value {
            return code
        }
        let message = comps?.queryItems?.first(where: { $0.name == "error_description" })?.value
            ?? comps?.queryItems?.first(where: { $0.name == "error" })?.value
            ?? "認証に失敗しました"
        throw AuthError.server(message)
    }

    // MARK: - トークン

    private static func exchange(code: String, verifier: String) async throws -> SupabaseSession {
        try await token(grantType: "pkce", body: ["auth_code": code, "code_verifier": verifier])
    }

    static func refresh(refreshToken: String) async throws -> SupabaseSession {
        try await token(grantType: "refresh_token", body: ["refresh_token": refreshToken])
    }

    private static func token(grantType: String, body: [String: String]) async throws -> SupabaseSession {
        var comps = URLComponents(url: authBase.appendingPathComponent("token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.server(Self.errorMessage(from: data) ?? "ログインに失敗しました")
        }
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    static func signOut(accessToken: String) async throws {
        var req = URLRequest(url: authBase.appendingPathComponent("logout"))
        req.httpMethod = "POST"
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["error_description"] as? String)
            ?? (json["msg"] as? String)
            ?? (json["message"] as? String)
            ?? (json["error"] as? String)
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
