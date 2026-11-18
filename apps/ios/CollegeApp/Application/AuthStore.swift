import Foundation
import Observation

/// ログイン状態・プロフィールを一元管理する。
///
/// ログインは hlab.college の Google アカウントで 1 回だけ行う:
/// 1. アプリが Google に直接ログインし（`GoogleAuth`）、access token / refresh token を得る
/// 2. access token を新 API の `POST /auth/google` に送る。サーバーが本人確認・ドメイン判定をして
///    無期限のセッショントークンを返す（`CollegeAPI.Session`）
/// どちらもキーチェーンに置き、明示的にログアウトするまで残す。以後ログイン画面は出ない。
/// Google のトークンはプライベートカレンダーへの投稿にだけ使う。
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private static let sessionKey = "college.authSession"
    private static let googleTokensKey = "google.tokens"

    private(set) var session: AuthSession?
    private(set) var profile: Profile?
    private(set) var loading = true
    var authError: String?

    var user: SessionUser? { session?.user }
    var isSignedIn: Bool { session != nil }

    private var googleRefreshTask: Task<GoogleAuth.Tokens, Error>?

    private init() {}

    // MARK: - 起動時復元

    func restore() async {
        defer { loading = false }

        // モックモードではダミーのセッションで自動ログインする（キーチェーンには保存しない）
        if AppConfig.useMockAPI {
            session = MockSeed.session
            await fetchProfile()
            return
        }

        // Supabase 時代のセッションが残っていれば捨てる（Supabase は廃止済み）
        KeychainStore.delete(key: "supabase.session")

        guard CollegeAPI.Session.token != nil,
              let data = KeychainStore.load(key: Self.sessionKey),
              let stored = try? JSONDecoder().decode(AuthSession.self, from: data)
        else { return }

        // オフラインでもログイン状態は保つ。サーバーがセッションを消していた場合は 401 → sessionRevoked で戻る
        session = stored
        await fetchProfile()
    }

    // MARK: - サインイン / サインアウト

    func signInWithGoogle() async {
        authError = nil
        if AppConfig.useMockAPI {
            session = MockSeed.session
            await fetchProfile()
            return
        }
        do {
            let tokens = try await GoogleAuth.signIn()
            let me: CollegeAPI.Me
            do {
                me = try await CollegeAPI.signIn(googleAccessToken: tokens.accessToken)
            } catch {
                // 許可外ドメインなどで断られたら、Google 側の許可も残さない
                await GoogleAuth.revoke(tokens.refreshToken ?? tokens.accessToken)
                throw error
            }
            saveGoogleTokens(tokens)
            persist(AuthSession(user: SessionUser(id: me.resident.id, email: me.email)))
            profile = Profile(me.resident)
        } catch AuthError.cancelled {
            // ユーザー自身のキャンセルなのでエラー表示はしない
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        await CollegeAPI.signOut()
        if let tokens = loadGoogleTokens() {
            await GoogleAuth.revoke(tokens.refreshToken ?? tokens.accessToken)
        }
        clearLocalSession()
    }

    /// 新 API が 401 を返した（サーバー側でセッションが消された）ときに呼ばれる。ログイン画面へ戻す
    func sessionRevoked() async {
        guard !AppConfig.useMockAPI, session != nil else { return }
        clearLocalSession()
        authError = "ログインの有効期限が切れました。もう一度ログインしてください"
    }

    private func clearLocalSession() {
        session = nil
        profile = nil
        googleRefreshTask = nil
        CollegeAPI.Session.clear()
        KeychainStore.delete(key: Self.sessionKey)
        KeychainStore.delete(key: Self.googleTokensKey)
    }

    private func persist(_ newSession: AuthSession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            KeychainStore.save(data, key: Self.sessionKey)
        }
    }

    // MARK: - Google の access token（プライベートカレンダー投稿用）

    /// 有効な Google の access token を返す。期限切れなら refresh token で更新する（同時呼び出しは 1 回にまとめる）
    func googleAccessToken() async throws -> String {
        guard let current = loadGoogleTokens() else {
            throw APIError.message("Googleカレンダーとの連携が必要です。一度ログアウトして再ログインしてください")
        }
        guard current.isExpired else { return current.accessToken }

        if let task = googleRefreshTask {
            return try await task.value.accessToken
        }
        guard let refreshToken = current.refreshToken else {
            throw APIError.message("Googleカレンダーとの連携が必要です。一度ログアウトして再ログインしてください")
        }
        let task = Task { try await GoogleAuth.refresh(refreshToken) }
        googleRefreshTask = task
        defer { googleRefreshTask = nil }

        do {
            let refreshed = try await task.value
            saveGoogleTokens(refreshed)
            return refreshed.accessToken
        } catch {
            throw APIError.message("Googleカレンダーとの連携が切れました。一度ログアウトして再ログインしてください")
        }
    }

    private func loadGoogleTokens() -> GoogleAuth.Tokens? {
        KeychainStore.load(key: Self.googleTokensKey).flatMap { try? JSONDecoder().decode(GoogleAuth.Tokens.self, from: $0) }
    }

    private func saveGoogleTokens(_ tokens: GoogleAuth.Tokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            KeychainStore.save(data, key: Self.googleTokensKey)
        }
    }

    // MARK: - プロフィール

    func fetchProfile() async {
        guard session != nil, let me = try? await CollegeAPI.me() else { return }
        profile = Profile(me.resident)
        if let email = me.email, session?.user.email != email {
            session?.user.email = email
            if let session { persist(session) }
        }
    }

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resident = try await CollegeAPI.updateMe(displayName: trimmed, bio: nil)
        profile = Profile(resident)
    }
}

private extension Profile {
    init(_ resident: Resident) {
        self.init(id: resident.id, display_name: resident.displayName, avatar_url: resident.avatarUrl)
    }
}
