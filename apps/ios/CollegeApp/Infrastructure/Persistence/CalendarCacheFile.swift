import Foundation

/// カレンダーの予定の端末内キャッシュ（Application Support/calendar-cache.json）。
///
/// 読んだ期間（日本時間の日付。両端を含む）の予定を、サーバーの版（`version`）と一緒に保存する。
/// 起動時はまずこれを表示し、サーバーには版だけを問い合わせる。版が同じならサーバーは予定を読まずに済む
struct CalendarCache: Codable {
    var version: String
    /// 読んだ期間 yyyy-MM-dd（両端を含む。途切れのない 1 区間）
    var from: String
    var to: String
    var events: [CalendarEvent]
    /// `to` より先にまだ予定があるか（サーバーは 60 日先まで同期している）
    var hasMore: Bool

    func covers(from: String, to: String) -> Bool {
        self.from <= from && to <= self.to
    }
}

enum CalendarCacheFile {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calendar-cache.json")
    }

    static func load() -> CalendarCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalendarCache.self, from: data)
    }

    static func save(_ cache: CalendarCache?) {
        guard let cache else { return clear() }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
