import Foundation
import Observation

/// カレンダーの予定。Web 版 `useEvents` の移植に、ページ読み込みと端末キャッシュを足したもの。
///
/// サーバー（D1）の読み込みを減らすため:
/// - 最初は今日から 30 日分だけ読み、カレンダーを一番下までスクロールしたら次の 30 日を読む（`loadMore`）
/// - 読んだ予定は版と一緒に端末に保存する（`CalendarCacheFile`）。起動時はキャッシュを表示し、サーバーには版だけを
///   問い合わせる。予定が変わっていなければサーバーは予定を読まない
/// - 版の問い合わせは、サーバーの同期間隔（15 分）より短い間隔では行わない（引っ張って更新したときを除く）
@MainActor
@Observable
final class EventsStore {
    private(set) var events: [CalendarEvent] = []
    /// キャッシュが無く、初回の読み込み中
    private(set) var loading = true
    private(set) var loadingMore = false
    private(set) var error: String?

    /// 一度に読む日数
    static let pageDays = 30
    /// 日記の「イベント」で使う過去の日数（サーバーの同期範囲と同じ）
    static let pastDays = 30
    /// 版の問い合わせの最短間隔（サーバーの同期間隔）
    private static let checkInterval: TimeInterval = 15 * 60

    private var cache: CalendarCache?
    private var lastChecked: Date?
    /// 投稿直後に一覧へ反映されるまでの間、楽観的に表示するイベント（プライベートの予定は一覧に載らないので、これで出す）
    private var localAdded: [CalendarEvent] = []

    init() {
        cache = CalendarCacheFile.load()
        loading = cache == nil
        rebuild()
    }

    /// まだ先の予定があるか（カレンダーの一番下で次を読むか）
    var hasMore: Bool { cache?.hasMore ?? true }
    /// 読み込み済みの最後の日。スクロールで次を読んだら変わる
    var loadedTo: String { cache?.to ?? "" }

    /// 画面を開いたとき。前回の確認から 15 分以内ならサーバーに問い合わせない
    func load() async {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval, cache != nil { return }
        await refresh()
    }

    /// 引っ張って更新したとき。今日から 30 日分の版を確かめ、変わっていれば読み直す
    func refresh() async {
        error = nil
        let from = DateUtil.dateKey(Date())
        let to = Self.addDays(Self.pageDays - 1, to: from)
        do {
            let known = cache?.covers(from: from, to: to) == true ? cache?.version : nil
            let page = try await CollegeAPI.calendarEvents(from: from, to: to, version: known)
            lastChecked = Date()
            if case .page(let version, let fetched, let more) = page {
                if version == cache?.version {
                    merge(from: from, to: to, events: fetched, hasMore: more)
                } else {
                    // 予定が変わった。ほかの期間のキャッシュも古いので捨て、今日から 30 日分だけにする
                    cache = CalendarCache(version: version, from: from, to: to, events: fetched, hasMore: more)
                }
                save()
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// カレンダーの一番下まで来たとき。次の 30 日を読む
    func loadMore() async {
        guard let cache, cache.hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let from = Self.addDays(1, to: cache.to)
        await fetch(from: from, to: Self.addDays(Self.pageDays - 1, to: from))
    }

    /// 日記の「イベント」用に、過去 30 日分も読んでおく
    func ensurePast() async {
        if cache == nil { await refresh() }
        guard let cache else { return }
        let from = Self.addDays(-Self.pastDays, to: DateUtil.dateKey(Date()))
        guard from < cache.from else { return }
        await fetch(from: from, to: Self.addDays(-1, to: cache.from))
    }

    func addLocalEvent(_ event: CalendarEvent) {
        guard !localAdded.contains(where: { $0.id == event.id }) else { return }
        localAdded.append(event)
        rebuild()
    }

    /// キャッシュに続く期間を読む。途中で予定が変わっていたら、キャッシュを捨てて今日から読み直してから、もう一度読む
    private func fetch(from: String, to: String, retry: Bool = true) async {
        do {
            let page = try await CollegeAPI.calendarEvents(from: from, to: to, version: nil)
            guard case .page(let version, let fetched, let more) = page else { return }
            guard version == cache?.version else {
                cache = nil
                await refresh()
                if retry, cache != nil { await fetch(from: from, to: to, retry: false) }
                return
            }
            merge(from: from, to: to, events: fetched, hasMore: more)
            save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 同じ版の期間をキャッシュにつなげる。つながらない期間なら（日付が大きく進んだときなど）そこだけにする
    private func merge(from: String, to: String, events fetched: [CalendarEvent], hasMore more: Bool) {
        guard var current = cache,
              from <= Self.addDays(1, to: current.to), Self.addDays(-1, to: current.from) <= to
        else {
            if let version = cache?.version {
                cache = CalendarCache(version: version, from: from, to: to, events: fetched, hasMore: more)
            }
            return
        }
        current.events = current.events.filter { $0.dateKey < from || $0.dateKey > to } + fetched
        if to >= current.to { current.hasMore = more }
        current.from = min(current.from, from)
        current.to = max(current.to, to)
        cache = current
    }

    private func save() {
        CalendarCacheFile.save(cache)
        rebuild()
    }

    /// キャッシュの予定 + まだ一覧に載っていないローカル追加分をマージし、繰り返しフラグを付与
    private func rebuild() {
        let fetched = (cache?.events ?? []).sorted { $0.startISO < $1.startISO }
        let fetchedIDs = Set(fetched.map(\.id))
        let pending = localAdded.filter { !fetchedIDs.contains($0.id) }
        let merged = pending + fetched

        var counts: [String: Int] = [:]
        for e in merged { counts[e.id, default: 0] += 1 }

        events = merged.map { event in
            var copy = event
            copy.isRecurring = event.isRecurring || (counts[event.id] ?? 0) > 1
            return copy
        }
    }

    private static func addDays(_ days: Int, to key: String) -> String {
        guard let date = DateUtil.date(fromKey: key),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: date)
        else { return key }
        return DateUtil.dateKey(moved)
    }
}
