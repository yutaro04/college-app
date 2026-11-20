import Foundation

/// 日記の「イベント」— みんなで撮る 2 秒クリップ（`/events`）
extension CollegeAPI {
    /// GET /events?from=&to= — クリップの投稿先になったイベントとクリップ数（yyyy-MM-dd）
    static func events(from: String, to: String) async throws -> [EventSummary] {
        struct Response: Decodable { let events: [EventSummary] }
        let body: Response = try await send(
            path: "/events", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        )
        return body.events
    }

    /// POST /events/resolve — カレンダーの予定に対応するイベントを用意してもらう（無ければ作られる）
    static func resolveEvent(_ event: CalendarEvent) async throws -> EventSummary {
        struct Body: Encodable {
            let calendarEventId: String
            let eventDate: String
        }
        struct Resolved: Decodable {
            let id: String
            let title: String
            let eventDate: String
            let calendarEventId: String?
        }
        struct Response: Decodable { let event: Resolved }
        let body: Response = try await send(
            path: "/events/resolve", method: "POST", json: Body(calendarEventId: event.id, eventDate: event.dateKey)
        )
        let e = body.event
        return EventSummary(id: e.id, title: e.title, eventDate: e.eventDate, calendarEventId: e.calendarEventId, clipCount: 0)
    }

    /// GET /events/:eventId/clips — みんなのクリップ（古い順）
    static func eventClips(eventId: String) async throws -> [EventClip] {
        struct Response: Decodable { let clips: [EventClip] }
        let body: Response = try await send(path: "/events/\(eventId)/clips")
        return body.clips
    }

    /// POST /events/:eventId/clips — 切り出し済みの mp4 を multipart で送る
    static func uploadEventClip(eventId: String, file: URL, durationMs: Int?) async throws -> EventClip {
        struct Response: Decodable { let clip: EventClip }
        var form = MultipartForm()
        if let durationMs { form.addField("durationMs", "\(durationMs)") }
        form.addFile("file", filename: "clip.mp4", contentType: "video/mp4", data: try Data(contentsOf: file))
        let body: Response = try await send(
            path: "/events/\(eventId)/clips", method: "POST", upload: form.finish()
        )
        return body.clip
    }

    /// GET /events/:eventId/clips/:clipId/file — 動画本体を destination に保存する
    static func downloadEventClip(_ clip: EventClip, to destination: URL) async throws {
        try await download(path: "/events/\(clip.eventId)/clips/\(clip.id)/file", to: destination)
    }

    /// DELETE /events/:eventId/clips/:clipId — 自分のクリップだけ消せる
    static func deleteEventClip(_ clip: EventClip) async throws {
        let _: Empty = try await send(path: "/events/\(clip.eventId)/clips/\(clip.id)", method: "DELETE")
    }
}

/// multipart/form-data の本文を組み立てる
struct MultipartForm {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(_ name: String, _ value: String) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data file: Data) {
        data.append(Data((
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                + "Content-Type: \(contentType)\r\n\r\n"
        ).utf8))
        data.append(file)
        data.append(Data("\r\n".utf8))
    }

    /// (本文, Content-Type)
    func finish() -> (Data, String) {
        var body = data
        body.append(Data("--\(boundary)--\r\n".utf8))
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}
