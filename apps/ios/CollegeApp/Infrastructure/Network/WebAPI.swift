import Foundation

/// Web 版（Next.js）の API Route を叩くクライアント。
///
/// イベント取得・投稿・Google 連携は service_role key / GAS シークレット / Google client secret を
/// 必要とするため、iOS 側では再実装せず既存のサーバーをそのまま経由する。
enum WebAPI {
    struct CalendarOption: Decodable, Hashable, Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    struct RoomOption: Decodable, Hashable, Identifiable {
        let label: String
        let email: String
        var id: String { email }
    }

    struct PostConfig: Decodable {
        let calendars: [CalendarOption]
        let rooms: [RoomOption]
    }

    struct CreateEventInput: Encodable {
        var calendarKey: String
        var title: String
        var description: String
        var location: String
        var roomEmail: String
        var attendees: [String]
        var isAllDay: Bool
        /// yyyy-MM-dd
        var dateKey: String
        var startISO: String
        var endISO: String
    }

    // MARK: - エンドポイント

    /// GET /api/events — EventCache スプレッドシート由来のイベント一覧
    static func fetchEvents() async throws -> [CalendarEvent] {
        struct Response: Decodable {
            let success: Bool
            let events: [CalendarEvent]?
            let error: String?
        }
        let body: Response = try await send(path: "/api/events", method: "GET")
        guard body.success else { throw APIError.message(body.error ?? "データ取得に失敗しました") }
        return body.events ?? []
    }

    /// GET /api/events/config — 投稿先カレンダーと ROOM の選択肢
    static func fetchPostConfig() async throws -> PostConfig {
        struct Response: Decodable {
            let success: Bool
            let config: PostConfig?
            let error: String?
        }
        let body: Response = try await send(path: "/api/events/config", method: "GET")
        guard body.success, let config = body.config else {
            throw APIError.message(body.error ?? "設定の取得に失敗しました")
        }
        return config
    }

    /// POST /api/events/create — イベント作成（GAS 経由 or 本人の Google カレンダー）
    static func createEvent(_ input: CreateEventInput, accessToken: String) async throws -> CalendarEvent {
        struct Response: Decodable {
            let success: Bool
            let event: CalendarEvent?
            let error: String?
        }
        let body: Response = try await send(
            path: "/api/events/create",
            method: "POST",
            json: try JSONEncoder().encode(input),
            accessToken: accessToken
        )
        guard body.success, let event = body.event else {
            throw APIError.message(body.error ?? "イベント作成に失敗しました")
        }
        return event
    }

    /// POST /api/auth/google-token — Google の refresh_token をサーバーへ保存
    static func saveGoogleRefreshToken(_ refreshToken: String, accessToken: String) async throws {
        struct Body: Encodable { let refreshToken: String }
        struct Response: Decodable { let success: Bool }
        _ = try await send(
            path: "/api/auth/google-token",
            method: "POST",
            json: try JSONEncoder().encode(Body(refreshToken: refreshToken)),
            accessToken: accessToken
        ) as Response
    }

    // MARK: - 実行

    private static func send<T: Decodable>(
        path: String, method: String, json: Data? = nil, accessToken: String? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.webAPIBaseURL) else {
            throw APIError.message("URL が不正です")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = json
        }
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.message("ネットワークエラー")
        }

        guard response is HTTPURLResponse else { throw APIError.message("通信に失敗しました") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // API Route が JSON 以外（502 の HTML など）を返した場合
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.message("サーバーから予期しない応答が返りました (\(status))")
        }
    }
}

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}
