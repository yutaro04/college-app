import Foundation
import Observation

/// Web 版 `useAddEvent` の移植。投稿フォームの設定取得とイベント作成を担う。
@MainActor
@Observable
final class AddEventStore {
    private(set) var config: WebAPI.PostConfig?
    private(set) var configError: String?
    private(set) var submitting = false

    /// GAS から設定を取れなかった場合のフォールバック（Web 版と同じ既定値）
    static let fallbackCalendars: [WebAPI.CalendarOption] = [
        .init(key: "event", name: "000_イベントカレンダー"),
        .init(key: "house", name: "001_ハウス/委員会"),
        .init(key: "private", name: "プライベート"),
    ]

    var calendars: [WebAPI.CalendarOption] { config?.calendars ?? Self.fallbackCalendars }
    var rooms: [WebAPI.RoomOption] { config?.rooms ?? [] }

    func loadConfig() async {
        guard config == nil else { return }
        do {
            config = try await WebAPI.fetchPostConfig()
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
    }

    func createEvent(_ input: WebAPI.CreateEventInput) async throws -> CalendarEvent {
        submitting = true
        defer { submitting = false }

        guard let token = try await AuthStore.shared.accessToken() else {
            throw APIError.message("ログインが必要です")
        }
        return try await WebAPI.createEvent(input, accessToken: token)
    }
}

/// Web 版 `useUserDirectory` + `useInviteGroups` の移植。招待先ピッカー用。
@MainActor
@Observable
final class InvitePickerStore {
    private(set) var directory: [DirectoryUser] = []
    private(set) var groups: [InviteGroup] = []

    func load() async {
        async let users = try? DB.fetch(
            "profiles",
            [DB.select("id,display_name,email"), DB.notIsNull("email")],
            as: DirectoryUser.self
        )
        async let myGroups = try? DB.fetch(
            "invite_groups",
            [DB.select("id,name,emails"), DB.order("created_at", ascending: true)],
            as: InviteGroup.self
        )
        directory = await users ?? []
        groups = await myGroups ?? []
    }

    func createGroup(name: String, emails: [String]) async throws {
        guard let userId = AuthStore.shared.user?.id else { return }
        struct NewGroup: Encodable {
            let owner_id: String
            let name: String
            let emails: [String]
        }
        let created: InviteGroup = try await DB.insert(
            "invite_groups",
            NewGroup(owner_id: userId, name: name, emails: emails),
            returning: InviteGroup.self
        )
        groups.append(created)
    }

    func deleteGroup(_ id: String) async throws {
        try await DB.delete("invite_groups", [DB.eq("id", id)])
        groups.removeAll { $0.id == id }
    }

    /// Web 版と同じ: 登録ユーザー → メーリングリストの順に最大 8 件
    func suggestions(query: String, selected: [String]) -> [InviteSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        let users = directory
            .filter { !selected.contains($0.email) }
            .filter { $0.display_name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
            .map { InviteSuggestion(label: "\($0.display_name)（\($0.email)）", email: $0.email) }

        let lists = MailingLists.all
            .filter { !selected.contains($0.email) }
            .filter { $0.label.lowercased().contains(q) || $0.email.lowercased().contains(q) }
            .map { InviteSuggestion(label: "\($0.label)（メーリングリスト）", email: $0.email) }

        return Array((users + lists).prefix(8))
    }
}
