import Foundation

/// 2 秒クリップの端末内保存先（Application Support/Clips 以下）。
///
/// バックエンド（R2 へのアップロード）が未実装のため、現状はクリップ本体を端末内にだけ保存する。
/// - 日常: `Clips/daily/<yyyy-MM-dd>.mp4`（1 日 1 本。撮り直しは上書き）
/// - イベント: `Clips/events/<eventKey>/<作成者 id>__<uuid>.mp4`
enum ClipFileStore {
    struct EventClip: Identifiable, Hashable {
        let url: URL
        let authorId: String
        let createdAt: Date

        var id: URL { url }
    }

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clips", isDirectory: true)
    }

    private static func directory(_ components: String...) -> URL {
        let url = components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 日常

    static func dailyURL(dateKey: String) -> URL {
        directory("daily").appendingPathComponent("\(dateKey).mp4")
    }

    /// 日付キー → ファイル
    static func dailyClips() -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory("daily"), includingPropertiesForKeys: nil)) ?? []
        return Dictionary(uniqueKeysWithValues: files
            .filter { $0.pathExtension == "mp4" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) })
    }

    static func deleteDaily(dateKey: String) {
        try? FileManager.default.removeItem(at: dailyURL(dateKey: dateKey))
    }

    // MARK: - イベント

    /// カレンダーのイベント ID はファイル名に使えない文字を含みうるので置き換える
    static func eventKey(for event: CalendarEvent) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(event.rowKey.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    static func newEventClipURL(eventKey: String, authorId: String) -> URL {
        directory("events", eventKey).appendingPathComponent("\(authorId)__\(UUID().uuidString).mp4")
    }

    static func eventClips(eventKey: String) -> [EventClip] {
        let dir = directory("events", eventKey)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "mp4" }
            .map { url in
                let author = url.deletingPathExtension().lastPathComponent.components(separatedBy: "__").first ?? ""
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return EventClip(url: url, authorId: author, createdAt: created)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func eventClipCount(eventKey: String) -> Int {
        let dir = root.appendingPathComponent("events/\(eventKey)", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".mp4") }.count
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 書き出し先

    /// 思い出ビデオの書き出し先（一時ファイル。共有・保存はユーザーが行う）
    static func newExportURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString).mp4")
    }
}
