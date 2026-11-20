import Foundation

/// 日記のイベントクリップのインメモリ状態（`events` / `event_video_clips` に対応）
struct MockEventClipState {
    struct EventRow {
        let id: String
        let calendarEventId: String
        let eventDate: String
        let title: String
    }

    var events: [EventRow] = []
    var clips: [EventClip] = []
}

/// `/events`（日記のイベントクリップ）。
/// モックのサーバーは動画本体を持たない。他の人のクリップは ID を `sampleClipPrefix` で始め、
/// アプリ側（`EventClipsStore`）がダウンロードの代わりにサンプル動画を作る。自分で投稿したものはアプリが手元に持っている
extension MockBackend {
    static let sampleClipPrefix = "sample-"

    func eventsAPI(method: String, path: [String], query: [URLQueryItem], input: [String: Any]) -> Reply {
        // path は ["events", ...]。`:eventId/clips/:clipId` は (method, ルート) に直して照合する
        let rest = Array(path.dropFirst())
        let eventId = rest.first ?? ""
        let clipId = rest.count > 2 ? rest[2] : ""
        let route = rest.enumerated().map { $0.offset == 0 && $0.element != "resolve" ? ":eventId" : $0.offset == 2 ? ":clipId" : $0.element }
            .joined(separator: "/")
        switch (method, route) {
        case ("GET", ""):
            let from = query.value("from") ?? "", to = query.value("to") ?? ""
            let list: [EventSummary] = eventClips.events
                .filter { $0.eventDate >= from && $0.eventDate <= to }
                .map { row in
                    EventSummary(
                        id: row.id, title: row.title, eventDate: row.eventDate, calendarEventId: row.calendarEventId,
                        clipCount: eventClips.clips.filter { $0.eventId == row.id }.count
                    )
                }
            return encode(["events": list])

        case ("POST", "resolve"):
            guard let calendarId = input["calendarEventId"] as? String, let date = input["eventDate"] as? String else {
                return error(400, "calendarEventId と eventDate（yyyy-MM-dd）を指定してください")
            }
            if let row = eventClips.events.first(where: { $0.calendarEventId == calendarId && $0.eventDate == date }) {
                return json(["event": eventJSON(row)])
            }
            guard let event = events.first(where: { $0.id == calendarId && $0.dateKey == date }) else {
                return error(404, "カレンダーにこのイベントが見つかりません")
            }
            let row = MockEventClipState.EventRow(
                id: "event_\(UUID().uuidString.prefix(8).lowercased())", calendarEventId: calendarId,
                eventDate: date, title: event.title
            )
            eventClips.events.append(row)
            seedSampleClips(eventId: row.id)
            return json(["event": eventJSON(row)])

        case ("GET", ":eventId/clips"):
            guard eventClips.events.contains(where: { $0.id == eventId }) else { return error(404, "イベントが見つかりません") }
            return encode(["clips": eventClips.clips.filter { $0.eventId == eventId }])

        case ("POST", ":eventId/clips"):
            guard eventClips.events.contains(where: { $0.id == eventId }) else { return error(404, "イベントが見つかりません") }
            let clip = EventClip(
                id: "clip_\(UUID().uuidString.prefix(8).lowercased())", eventId: eventId, residentId: myId,
                author: ref(myId)!, durationMs: 2000, createdAt: ISODate.string(from: Date())
            )
            eventClips.clips.append(clip)
            return encode(["clip": clip], status: 201)

        case ("DELETE", ":eventId/clips/:clipId"):
            guard let clip = eventClips.clips.first(where: { $0.id == clipId && $0.eventId == eventId }) else {
                return error(404, "クリップが見つかりません")
            }
            guard clip.residentId == myId else { return error(403, "自分のクリップだけ削除できます") }
            eventClips.clips.removeAll { $0.id == clipId }
            return Reply(status: 204, data: Data())

        default:
            return notFound()
        }
    }

    private func eventJSON(_ row: MockEventClipState.EventRow) -> [String: Any] {
        ["id": row.id, "title": row.title, "eventDate": row.eventDate, "calendarEventId": row.calendarEventId]
    }

    /// 他の居住者が撮ったことにしたクリップを 3 本入れておく
    private func seedSampleClips(eventId: String) {
        let authors = residents.filter { $0.id != myId }.shuffled().prefix(3)
        for (index, author) in authors.enumerated() {
            guard let ref = ref(author.id) else { continue }
            eventClips.clips.append(EventClip(
                id: "\(Self.sampleClipPrefix)\(UUID().uuidString.prefix(8).lowercased())", eventId: eventId,
                residentId: author.id, author: ref, durationMs: 2000,
                createdAt: MockSeed.iso(minutesAgo: 90 - index * 20)
            ))
        }
    }
}
