import Foundation

/// 日記の「イベント」用の 2 秒クリップ（`services/api` の `event_video_clips`）。参加者みんなで撮ってみんなで見る。
/// 動画本体は `GET /events/:eventId/clips/:clipId/file` から取り、端末にキャッシュする（`ClipFileStore`）
struct EventClip: Codable, Identifiable, Hashable {
    let id: String
    let eventId: String
    let residentId: String
    let author: ResidentRef
    let durationMs: Int?
    let createdAt: String
}

/// クリップの投稿先になったイベント（`events` の行）とクリップ数。
/// カレンダーの予定とは `calendarEventId` + `eventDate`（= `CalendarEvent.id` + `dateKey`）で対応する
struct EventSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let eventDate: String
    let calendarEventId: String?
    let clipCount: Int
}
