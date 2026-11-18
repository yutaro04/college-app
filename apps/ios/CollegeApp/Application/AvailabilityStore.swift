import Foundation
import Observation

/// いまひま（「今ひま」の表明と、それへの「誘う」）。新 API の `/hima-statuses` を使う。
///
/// 新着の誘いは 30 秒ごとのポーリングで検知する。
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
            entries = try await CollegeAPI.himaStatuses()
            myEntry = entries.first { $0.user_id == AuthStore.shared.user?.id }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func fetchInvites(notifyNew: Bool) async {
        guard AuthStore.shared.user != nil, let fetched = try? await CollegeAPI.himaInvites() else { return }

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

    /// 暇を表明する。既存の表明は置き換わる（紐づく誘いも消える）
    func post(message: String, expiresAt: Date) async throws {
        try await CollegeAPI.postHima(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines), expiresAt: expiresAt
        )
        await fetchEntries()
    }

    func clear() async throws {
        try await CollegeAPI.clearHima()
        await fetchEntries()
    }

    func invite(_ target: AvailabilityEntry, message: String) async throws {
        try await CollegeAPI.inviteHima(
            statusId: target.id, message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
