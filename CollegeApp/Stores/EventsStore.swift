import Foundation
import Observation

/// Web 版 `useEvents` の移植。
@MainActor
@Observable
final class EventsStore {
    private(set) var events: [CalendarEvent] = []
    private(set) var loading = true
    private(set) var error: String?

    private var csvEvents: [CalendarEvent] = []
    /// 投稿直後に EventCache へ反映されるまでの間、楽観的に表示するイベント
    private var localAdded: [CalendarEvent] = []

    func load() async {
        loading = true
        error = nil
        do {
            csvEvents = try await WebAPI.fetchEvents()
        } catch {
            self.error = error.localizedDescription
        }
        rebuild()
        loading = false
    }

    /// プルトゥリフレッシュ用（ローディング画面に戻さず再取得する）
    func refresh() async {
        error = nil
        do {
            csvEvents = try await WebAPI.fetchEvents()
            rebuild()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addLocalEvent(_ event: CalendarEvent) {
        guard !localAdded.contains(where: { $0.id == event.id }) else { return }
        localAdded.append(event)
        rebuild()
    }

    /// CSV イベント + まだ CSV に載っていないローカル追加分をマージし、繰り返しフラグを付与
    private func rebuild() {
        let csvIDs = Set(csvEvents.map(\.id))
        let pending = localAdded.filter { !csvIDs.contains($0.id) }
        let merged = pending + csvEvents

        var counts: [String: Int] = [:]
        for e in merged { counts[e.id, default: 0] += 1 }

        events = merged.map { event in
            var copy = event
            copy.isRecurring = (counts[event.id] ?? 0) > 1
            return copy
        }
    }
}
