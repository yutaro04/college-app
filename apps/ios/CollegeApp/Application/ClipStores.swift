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

/// イベントごとのクリップ。参加者みんなで撮って、みんなで見る
@MainActor
@Observable
final class EventClipsStore {
    private(set) var clipsByEvent: [String: [ClipFileStore.EventClip]] = [:]
    private(set) var preparingSamples = false

    func clips(for event: CalendarEvent) -> [ClipFileStore.EventClip] {
        clipsByEvent[ClipFileStore.eventKey(for: event)] ?? []
    }

    func count(for event: CalendarEvent) -> Int {
        clipsByEvent[ClipFileStore.eventKey(for: event)]?.count ?? ClipFileStore.eventClipCount(eventKey: ClipFileStore.eventKey(for: event))
    }

    func load(_ event: CalendarEvent) async {
        let key = ClipFileStore.eventKey(for: event)
        var clips = ClipFileStore.eventClips(eventKey: key)
        if AppConfig.useMockAPI, clips.isEmpty {
            await seedSamples(for: event, key: key)
            clips = ClipFileStore.eventClips(eventKey: key)
        }
        clipsByEvent[key] = clips
    }

    func add(source: URL, to event: CalendarEvent, authorId: String) async throws {
        let key = ClipFileStore.eventKey(for: event)
        let destination = ClipFileStore.newEventClipURL(eventKey: key, authorId: authorId)
        try await ClipProcessing.trimToClip(source: source, destination: destination)
        clipsByEvent[key] = ClipFileStore.eventClips(eventKey: key)
    }

    func delete(_ clip: ClipFileStore.EventClip, from event: CalendarEvent) {
        ClipFileStore.delete(clip.url)
        let key = ClipFileStore.eventKey(for: event)
        clipsByEvent[key] = ClipFileStore.eventClips(eventKey: key)
    }

    /// イベントの思い出ビデオは居住者が用意した音源が必須（`event_memory_videos.music_r2_key` が NOT NULL）
    func compose(_ event: CalendarEvent, music: URL) async throws -> URL {
        let output = ClipFileStore.newExportURL()
        try await MemoryVideoComposer.compose(clips: clips(for: event).map(\.url), music: music, to: output)
        return output
    }

    /// モック用: 他の居住者が撮ったことにしたサンプルを 3 本作る
    private func seedSamples(for event: CalendarEvent, key: String) async {
        preparingSamples = true
        defer { preparingSamples = false }
        let authors = MockSeed.residents.filter { $0.id != MockSeed.myId }.shuffled().prefix(3)
        for (index, author) in authors.enumerated() {
            try? await SampleClipGenerator.generate(
                to: ClipFileStore.newEventClipURL(eventKey: key, authorId: author.id),
                title: event.title.count > 10 ? String(event.title.prefix(10)) + "…" : event.title,
                subtitle: "by \(author.name)",
                hue: CGFloat(index) * 0.3 + 0.05
            )
        }
    }
}
