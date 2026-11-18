import Foundation
import Observation

/// Web 版 `useAuth` の移植。セッション・プロフィール・ログイン状態を一元管理する。
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private static let sessionKey = "supabase.session"

    private(set) var session: SupabaseSession?
    private(set) var profile: Profile?
    private(set) var loading = true
    var authError: String?

    var user: SupabaseUser? { session?.user }
    var isSignedIn: Bool { session != nil }

    private var refreshTask: Task<SupabaseSession?, Error>?

    private init() {}

    // MARK: - 起動時復元

    /// キーチェーンのセッションを復元する。失効していればローカルをクリアして未ログインに戻す。
    func restore() async {
        defer { loading = false }

        // モックモードではダミーのセッションで自動ログインする（キーチェーンには保存しない）
        if AppConfig.useMockAPI {
            session = MockSeed.session
            await fetchProfile()
            return
        }

        guard let data = KeychainStore.load(key: Self.sessionKey),
              let stored = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        else { return }

        guard SupabaseAuth.isAllowed(email: stored.user.email) else {
            clearLocalSession()
            authError = "\(AppConfig.allowedDomain) のアカウントでログインしてください"
            return
        }

        session = stored
        // リフレッシュトークンが失効している場合はここで弾かれるので未ログインに戻す
        guard (try? await accessToken()) != nil else {
            clearLocalSession()
            return
        }
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
            let newSession = try await SupabaseAuth.signInWithGoogle()
            persist(newSession)
            await fetchProfile()
            await saveGoogleRefreshToken()
        } catch AuthError.cancelled {
            // ユーザー自身のキャンセルなのでエラー表示はしない
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        if let token = session?.accessToken {
            try? await SupabaseAuth.signOut(accessToken: token)
        }
        clearLocalSession()
    }

    private func clearLocalSession() {
        session = nil
        profile = nil
        refreshTask = nil
        KeychainStore.delete(key: Self.sessionKey)
    }

    private func persist(_ newSession: SupabaseSession) {
        // リフレッシュ時は provider_refresh_token が返らないので、既存の値を引き継ぐ
        var merged = newSession
        if merged.providerRefreshToken == nil { merged.providerRefreshToken = session?.providerRefreshToken }
        session = merged
        if let data = try? JSONEncoder().encode(merged) {
            KeychainStore.save(data, key: Self.sessionKey)
        }
    }

    // MARK: - アクセストークン

    /// 有効なアクセストークンを返す。期限切れならリフレッシュする。
    /// 同時に複数のリクエストが来てもリフレッシュは 1 回にまとめる。
    func accessToken() async throws -> String? {
        guard let current = session else { return nil }
        guard current.isExpired else { return current.accessToken }

        if let task = refreshTask {
            return try await task.value?.accessToken
        }

        let task = Task<SupabaseSession?, Error> { [refreshToken = current.refreshToken] in
            try await SupabaseAuth.refresh(refreshToken: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            guard let refreshed = try await task.value else { return nil }
            persist(refreshed)
            return refreshed.accessToken
        } catch {
            // Invalid Refresh Token など: 古いセッションを捨てて未ログインに戻す
            clearLocalSession()
            return nil
        }
    }

    // MARK: - プロフィール

    func fetchProfile() async {
        guard let userId = session?.user.id else { return }
        let rows = try? await DB.fetch(
            "profiles",
            [DB.select("id,display_name,avatar_url"), DB.eq("id", userId), DB.limit(1)],
            as: Profile.self
        )
        if let first = rows?.first { profile = first }
    }

    func updateDisplayName(_ name: String) async throws {
        guard let userId = session?.user.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        struct Patch: Encodable {
            let display_name: String
            let updated_at: String
        }
        try await DB.update(
            "profiles",
            Patch(display_name: trimmed, updated_at: ISODate.string(from: Date())),
            [DB.eq("id", userId)]
        )
        profile?.display_name = trimmed
    }

    // MARK: - Google refresh_token のサーバー保存

    /// 「プライベート」カレンダー投稿用に、Google の refresh_token を Web 版のサーバーへ預ける。
    /// 失敗してもログイン自体は継続する（プライベート投稿時にだけエラーになる）。
    private func saveGoogleRefreshToken() async {
        guard let session, let providerRefreshToken = session.providerRefreshToken else { return }
        try? await WebAPI.saveGoogleRefreshToken(providerRefreshToken, accessToken: session.accessToken)
    }
}
