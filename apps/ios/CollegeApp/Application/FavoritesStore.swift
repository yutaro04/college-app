import Foundation
import Observation

/// Web 版 `useFavorites` の移植。localStorage の代わりに UserDefaults に保存する。
@MainActor
@Observable
final class FavoritesStore {
    private static let storageKey = "cal_favorites"

    private(set) var ids: Set<String> = []

    init() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] {
            ids = Set(stored)
        }
    }

    func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    /// お気に入りを切り替え、切り替え後の状態を返す
    @discardableResult
    func toggle(_ id: String) -> Bool {
        let added: Bool
        if ids.contains(id) {
            ids.remove(id)
            added = false
        } else {
            ids.insert(id)
            added = true
        }
        persist()
        return added
    }

    func add(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: Self.storageKey)
    }
}

/// Web 版 `useMyCreatedEvents` の移植。MY EVENT タブ用に自分が作成したイベント ID を持つ。
@MainActor
@Observable
final class MyCreatedEventsStore {
    private(set) var ids: Set<String> = []

    func refresh() async {
        guard AuthStore.shared.user != nil else {
            ids = []
            return
        }
        let eventIds = try? await CollegeAPI.myCalendarEventIds()
        ids = Set(eventIds ?? [])
    }

    func add(_ id: String) { ids.insert(id) }

    func isMine(_ id: String) -> Bool { ids.contains(id) }
}
