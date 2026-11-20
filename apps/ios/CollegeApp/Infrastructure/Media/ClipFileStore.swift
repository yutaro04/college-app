import Foundation

/// 2 秒クリップの端末内保存先（Application Support/Clips 以下）。
///
/// - 日常: `Clips/daily/<yyyy-MM-dd>.mp4`（1 日 1 本。撮り直しは上書き）。アップロード API（`/daily-clips`）が
///   未実装のため、日常のクリップは端末内にだけある
/// - イベント: `Clips/event-cache/<eventId>/<clipId>.mp4`。正はサーバー（R2）で、ここはダウンロードしたもののキャッシュ
enum ClipFileStore {
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

    /// サーバーから取ったイベントクリップのキャッシュ。クリップの中身は変わらないので、一度取れば取り直さない
    static func eventClipURL(_ clip: EventClip) -> URL {
        directory("event-cache", safe(clip.eventId)).appendingPathComponent("\(safe(clip.id)).mp4")
    }

    static func isCached(_ clip: EventClip) -> Bool {
        FileManager.default.fileExists(atPath: eventClipURL(clip).path)
    }

    /// 投稿前に切り出したクリップの一時置き場（投稿できたら `eventClipURL` に移す）
    static func newPendingClipURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// ID はサーバー由来なので、ファイル名に使えない文字を置き換えておく
    private static func safe(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    // MARK: - 書き出し先

    /// 思い出ビデオの書き出し先（一時ファイル。共有・保存はユーザーが行う）
    static func newExportURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString).mp4")
    }
}
