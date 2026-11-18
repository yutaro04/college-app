import Foundation
import Observation

/// Web 版 `useAddEvent` の移植。投稿フォームの設定取得とイベント作成を担う。
@MainActor
@Observable
final class AddEventStore {
    private(set) var config: CollegeAPI.PostConfig?
    private(set) var configError: String?
    private(set) var submitting = false

    /// GAS から設定を取れなかった場合のフォールバック（Web 版と同じ既定値）
    static let fallbackCalendars: [CollegeAPI.CalendarOption] = [
        .init(key: "event", name: "000_イベントカレンダー"),
        .init(key: "house", name: "001_ハウス/委員会"),
        .init(key: "private", name: "プライベート"),
    ]

    var calendars: [CollegeAPI.CalendarOption] { config?.calendars ?? Self.fallbackCalendars }
    var rooms: [CollegeAPI.RoomOption] { config?.rooms ?? [] }

    func loadConfig() async {
        guard config == nil else { return }
        do {
            config = try await CollegeAPI.calendarPostConfig()
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
    }

    func createEvent(_ input: CollegeAPI.CalendarEventInput) async throws -> CalendarEvent {
        submitting = true
        defer { submitting = false }

        // プライベートは本人の Google カレンダーに作るので、本人の Google access token を渡す
        let googleToken = input.calendarKey == "private" ? try await AuthStore.shared.googleAccessToken() : nil
        return try await CollegeAPI.createCalendarEvent(input, googleAccessToken: googleToken)
    }
}

/// Web 版 `useUserDirectory` + `useInviteGroups` の移植。招待先ピッカー用。
@MainActor
@Observable
final class InvitePickerStore {
    private(set) var directory: [DirectoryUser] = []
    private(set) var groups: [InviteGroup] = []

    func load() async {
        async let users = try? CollegeAPI.inviteDirectory()
        async let myGroups = try? CollegeAPI.inviteGroups()
        directory = await users ?? []
        groups = await myGroups ?? []
    }

    func createGroup(name: String, emails: [String]) async throws {
        let created = try await CollegeAPI.createInviteGroup(name: name, emails: emails)
        groups.append(created)
    }

    func deleteGroup(_ id: String) async throws {
        try await CollegeAPI.deleteInviteGroup(id: id)
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
