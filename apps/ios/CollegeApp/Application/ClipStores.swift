import Foundation
import Observation

/// 日記（setlog 風）。1 日 1 本の 2 秒クリップ。本人だけが見る
@MainActor
@Observable
final class DiaryStore {
    /// 日付キー（yyyy-MM-dd） → クリップ
    private(set) var clips: [String: URL] = [:]
    private(set) var preparingSamples = false
    /// サムネイル更新用。撮り直しで同じ URL が上書きされたときに View を作り直す
    private(set) var revision = 0

    private static let seededKey = "mock.diarySeeded"

    var todayKey: String { DateUtil.dateKey(Date()) }

    /// 今日（今日まだなら昨日）から遡って何日続いているか
    var streak: Int {
        var day = Date()
        if clips[DateUtil.dateKey(day)] == nil {
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while clips[DateUtil.dateKey(day)] != nil {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    func load() async {
        clips = ClipFileStore.dailyClips()
        if AppConfig.useMockAPI, clips.isEmpty, !UserDefaults.standard.bool(forKey: Self.seededKey) {
            await seedSamples()
        }
    }

    /// 撮影・選択した動画の先頭 2 秒をその日のクリップとして保存（撮り直しは上書き）
    func save(source: URL, dateKey: String) async throws {
        let destination = ClipFileStore.dailyURL(dateKey: dateKey)
        try await ClipProcessing.trimToClip(source: source, destination: destination)
        ThumbnailCache.shared.invalidate(destination)
        clips[dateKey] = destination
        revision += 1
    }

    func delete(dateKey: String) {
        guard let url = clips[dateKey] else { return }
        ClipFileStore.deleteDaily(dateKey: dateKey)
        ThumbnailCache.shared.invalidate(url)
        clips[dateKey] = nil
        revision += 1
    }

    /// 期間内のクリップ（日付順）
    func clips(from start: Date, to end: Date) -> [(dateKey: String, url: URL)] {
        let startKey = DateUtil.dateKey(start)
        let endKey = DateUtil.dateKey(end)
        return clips.filter { $0.key >= startKey && $0.key <= endKey }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    func compose(from start: Date, to end: Date, music: URL?) async throws -> URL {
        let output = ClipFileStore.newExportURL()
        try await MemoryVideoComposer.compose(clips: clips(from: start, to: end).map(\.url), music: music, to: output)
        return output
    }

    /// モック用: 過去 2 週間分（ところどころ抜け）のサンプルを作る
    private func seedSamples() async {
        preparingSamples = true
        defer { preparingSamples = false }
        let moments = ["朝ごはん", "屋上の空", "ラウンジ", "通学路", "夕焼け", "共用キッチン", "下北の路地", "銭湯帰り"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E)"
        for offset in 1...14 where ![4, 9].contains(offset) {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = DateUtil.dateKey(date)
            try? await SampleClipGenerator.generate(
                to: ClipFileStore.dailyURL(dateKey: key),
                title: formatter.string(from: date),
                subtitle: moments[offset % moments.count],
                hue: CGFloat(offset) / 14
            )
        }
        UserDefaults.standard.set(true, forKey: Self.seededKey)
        clips = ClipFileStore.dailyClips()
    }
}

/// イベントごとのクリップ。参加者みんなで撮って、みんなで見る。
///
/// クリップは新 API（`/events`）に上げて共有する。動画本体は R2 にあり、見るときに端末へダウンロードしてキャッシュする
/// （`ClipFileStore.eventClipURL`）。カレンダーの予定とサーバーのイベントは `CalendarEvent.rowKey`（ID + 日付）で対応させる
@MainActor
@Observable
final class EventClipsStore {
    private(set) var clipsByEvent: [String: [EventClip]] = [:]
    /// rowKey → クリップ数（一覧用。`GET /events` の結果）
    private(set) var counts: [String: Int] = [:]
    /// rowKey → サーバーのイベント ID
    private var eventIds: [String: String] = [:]
    /// ダウンロード済み（キャッシュにある）クリップの ID。サムネイルの表示切り替えに使う
    private(set) var cached: Set<String> = []
    private(set) var loading = false
    private(set) var error: String?

    /// 一覧で数を出す範囲（カレンダーの同期範囲 = 過去 30 日より少し広め）
    private static let countDays = 60

    func clips(for event: CalendarEvent) -> [EventClip] {
        clipsByEvent[event.rowKey] ?? []
    }

    func count(for event: CalendarEvent) -> Int {
        clipsByEvent[event.rowKey]?.count ?? counts[event.rowKey] ?? 0
    }

    /// キャッシュにあればそのファイル。まだダウンロード中なら nil
    func localURL(_ clip: EventClip) -> URL? {
        cached.contains(clip.id) ? ClipFileStore.eventClipURL(clip) : nil
    }

    /// 一覧用に、最近のイベントのクリップ数をまとめて取る
    func loadCounts() async {
        let today = Date()
        let from = Calendar.current.date(byAdding: .day, value: -Self.countDays, to: today)!
        guard let events = try? await CollegeAPI.events(from: DateUtil.dateKey(from), to: DateUtil.dateKey(today)) else {
            return
        }
        for event in events {
            guard let calendarId = event.calendarEventId else { continue }
            let key = "\(calendarId)-\(event.eventDate)"
            counts[key] = event.clipCount
            eventIds[key] = event.id
        }
    }

    /// イベントを開いたとき: クリップ一覧を取り、まだ手元に無い動画をダウンロードする
    func load(_ event: CalendarEvent) async {
        loading = clipsByEvent[event.rowKey] == nil
        error = nil
        defer { loading = false }
        do {
            let eventId = try await resolve(event)
            let clips = try await CollegeAPI.eventClips(eventId: eventId)
            clipsByEvent[event.rowKey] = clips
            counts[event.rowKey] = clips.count
            await fetchFiles(clips)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(source: URL, to event: CalendarEvent) async throws {
        let eventId = try await resolve(event)
        let trimmed = ClipFileStore.newPendingClipURL()
        defer { ClipFileStore.delete(trimmed) }
        try await ClipProcessing.trimToClip(source: source, destination: trimmed)
        let durationMs = await ClipProcessing.durationMs(of: trimmed)
        let clip = try await CollegeAPI.uploadEventClip(eventId: eventId, file: trimmed, durationMs: durationMs)
        // 自分で撮ったものはダウンロードし直さずにキャッシュへ移す
        try? FileManager.default.moveItem(at: trimmed, to: ClipFileStore.eventClipURL(clip))
        if ClipFileStore.isCached(clip) { cached.insert(clip.id) }
        clipsByEvent[event.rowKey, default: []].append(clip)
        counts[event.rowKey] = clipsByEvent[event.rowKey]?.count
    }

    func delete(_ clip: EventClip, from event: CalendarEvent) async throws {
        try await CollegeAPI.deleteEventClip(clip)
        ClipFileStore.delete(ClipFileStore.eventClipURL(clip))
        cached.remove(clip.id)
        clipsByEvent[event.rowKey]?.removeAll { $0.id == clip.id }
        counts[event.rowKey] = clipsByEvent[event.rowKey]?.count
    }

    /// イベントの思い出ビデオは居住者が用意した音源が必須（`event_memory_videos.music_r2_key` が NOT NULL）。
    /// まだダウンロードできていないクリップは入れない
    func compose(_ event: CalendarEvent, music: URL) async throws -> URL {
        let output = ClipFileStore.newExportURL()
        try await MemoryVideoComposer.compose(clips: clips(for: event).compactMap(localURL), music: music, to: output)
        return output
    }

    private func resolve(_ event: CalendarEvent) async throws -> String {
        if let id = eventIds[event.rowKey] { return id }
        let id = try await CollegeAPI.resolveEvent(event).id
        eventIds[event.rowKey] = id
        return id
    }

    /// キャッシュに無い動画を 3 本ずつ並行して取る
    private func fetchFiles(_ clips: [EventClip]) async {
        for clip in clips where ClipFileStore.isCached(clip) { cached.insert(clip.id) }
        let missing = clips.filter { !cached.contains($0.id) }
        for batch in stride(from: 0, to: missing.count, by: 3).map({ Array(missing[$0..<min($0 + 3, missing.count)]) }) {
            await withTaskGroup(of: String?.self) { group in
                for clip in batch {
                    group.addTask { await Self.fetch(clip) ? clip.id : nil }
                }
                for await id in group {
                    if let id { cached.insert(id) }
                }
            }
        }
    }

    private nonisolated static func fetch(_ clip: EventClip) async -> Bool {
        let destination = ClipFileStore.eventClipURL(clip)
        if AppConfig.useMockAPI, clip.id.hasPrefix(MockBackend.sampleClipPrefix) {
            // モックのサーバーは動画本体を持たないので、他の人が撮ったことにしたサンプルをその場で作る
            return (try? await SampleClipGenerator.generate(
                to: destination, title: "サンプル", subtitle: "by \(clip.author.displayName)",
                hue: CGFloat(UInt(bitPattern: clip.id.hashValue) % 100) / 100
            )) != nil
        }
        return (try? await CollegeAPI.downloadEventClip(clip, to: destination)) != nil
    }
}
