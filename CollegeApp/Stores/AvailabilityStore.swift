import Foundation
import Observation
import UserNotifications

/// Web 版 `useAvailability` の移植。
///
/// Web 版は Supabase Realtime + 30 秒ポーリングの二重構成だったが、
/// iOS では WebSocket を持ち込まずポーリングに一本化している（新着検知のロジックは同じ）。
@MainActor
@Observable
final class AvailabilityStore {
    private(set) var entries: [AvailabilityEntry] = []
    private(set) var myEntry: AvailabilityEntry?
    private(set) var invites: [AvailabilityInvite] = []
    private(set) var loading = true
    private(set) var error: String?

    /// 新しい誘いを受け取ったときにトーストを出すためのコールバック
    var onInviteReceived: ((String, String) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var lastInviteID: String?

    private let embeddedEntryColumns = "id,user_id,message,expires_at,created_at,profiles!availability_user_id_fkey(display_name)"
    private let embeddedInviteColumns = "id,inviter_id,message,created_at,profiles!availability_invites_inviter_id_fkey(display_name)"

    // MARK: - ライフサイクル

    func start() async {
        guard AuthStore.shared.user != nil else {
            loading = false
            return
        }
        await fetchEntries()
        await fetchInvites(notifyNew: false)
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.fetchEntries()
                await self?.fetchInvites(notifyNew: true)
            }
        }
    }

    // MARK: - 取得

    func fetchEntries() async {
        error = nil
        do {
            let rows = try await DB.fetch(
                "availability",
                [
                    DB.select(embeddedEntryColumns),
                    DB.gt("expires_at", ISODate.string(from: Date())),
                    DB.order("created_at", ascending: false),
                ],
                as: AvailabilityRow.self
            )
            entries = rows.map(\.entry)
            myEntry = entries.first { $0.user_id == AuthStore.shared.user?.id }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func fetchInvites(notifyNew: Bool) async {
        guard let userId = AuthStore.shared.user?.id else { return }
        guard let rows = try? await DB.fetch(
            "availability_invites",
            [
                DB.select(embeddedInviteColumns),
                DB.eq("availability_user_id", userId),
                DB.order("created_at", ascending: false),
                DB.limit(50),
            ],
            as: InviteRow.self
        ) else { return }

        let fetched = rows.map(\.invite)

        // 前回の先頭より新しいものを新着とみなす（Web 版と同じ判定）
        if notifyNew, let previousTop = lastInviteID, fetched.first?.id != previousTop {
            for invite in fetched {
                if invite.id == previousTop { break }
                notify(invite)
            }
        }

        invites = fetched
        lastInviteID = fetched.first?.id
    }

    private func notify(_ invite: AvailabilityInvite) {
        let body = invite.message.isEmpty
            ? "\(invite.inviter_name)さんが誘っています"
            : "\(invite.inviter_name)さん: \(invite.message)"
        LocalNotifier.show(title: "ゆる募 / ひま", body: body)
        onInviteReceived?(invite.inviter_name, invite.message)
    }

    // MARK: - 更新

    /// 暇を表明する。既存の投稿は削除してから作り直す（cascade で紐づく誘いも消える）。
    func post(message: String, expiresAt: Date) async throws {
        guard let userId = AuthStore.shared.user?.id else { return }
        try await DB.delete("availability", [DB.eq("user_id", userId)])

        struct NewEntry: Encodable {
            let user_id: String
            let message: String
            let expires_at: String
        }
        try await DB.insert("availability", NewEntry(
            user_id: userId,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            expires_at: ISODate.string(from: expiresAt)
        ))
        await fetchEntries()
    }

    func clear() async throws {
        guard let userId = AuthStore.shared.user?.id else { return }
        try await DB.delete("availability", [DB.eq("user_id", userId)])
        await fetchEntries()
    }

    func invite(_ target: AvailabilityEntry, message: String) async throws {
        guard let userId = AuthStore.shared.user?.id else { return }
        struct NewInvite: Encodable {
            let availability_id: String
            let availability_user_id: String
            let inviter_id: String
            let message: String
        }
        try await DB.insert("availability_invites", NewInvite(
            availability_id: target.id,
            availability_user_id: target.user_id,
            inviter_id: userId,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }
}

/// Web 版の Service Worker 通知に相当するローカル通知
enum LocalNotifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
