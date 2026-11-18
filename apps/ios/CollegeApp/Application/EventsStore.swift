import Foundation
import Observation

/// Web 版 `useEvents` の移植。
@MainActor
@Observable
final class EventsStore {
    private(set) var events: [CalendarEvent] = []
    private(set) var loading = true
    private(set) var error: String?

    private var fetched: [CalendarEvent] = []
    /// 投稿直後に一覧へ反映されるまでの間、楽観的に表示するイベント（プライベートの予定は一覧に載らないので、これで出す）
    private var localAdded: [CalendarEvent] = []

    func load() async {
        loading = true
        error = nil
        do {
            fetched = try await CollegeAPI.calendarEvents()
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
            fetched = try await CollegeAPI.calendarEvents()
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

    /// 取得したイベント + まだ一覧に載っていないローカル追加分をマージし、繰り返しフラグを付与
    private func rebuild() {
        let fetchedIDs = Set(fetched.map(\.id))
        let pending = localAdded.filter { !fetchedIDs.contains($0.id) }
        let merged = pending + fetched

        var counts: [String: Int] = [:]
        for e in merged { counts[e.id, default: 0] += 1 }

        events = merged.map { event in
            var copy = event
            copy.isRecurring = (counts[event.id] ?? 0) > 1
            return copy
        }
    }
}
