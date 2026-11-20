import Foundation

/// 既存機能（いまひま・カレンダー招待・カレンダー）のエンドポイント。
/// 以前は Supabase と Next.js の `/api/events*` が担っていたもの
extension CollegeAPI {

    // MARK: - いまひま

    private struct HimaStatusDTO: Decodable {
        let id: String
        let resident: ResidentRef
        let message: String
        let expiresAt: String
        let createdAt: String

        var entry: AvailabilityEntry {
            AvailabilityEntry(
                id: id, user_id: resident.id, display_name: resident.displayName,
                message: message, expires_at: expiresAt, created_at: createdAt
            )
        }
    }

    private struct HimaInviteDTO: Decodable {
        let id: String
        let inviter: ResidentRef
        let message: String
        let createdAt: String

        var invite: AvailabilityInvite {
            AvailabilityInvite(
                id: id, inviter_id: inviter.id, inviter_name: inviter.displayName,
                message: message, created_at: createdAt
            )
        }
    }

    /// GET /hima-statuses — 期限内の表明（新しい順）
    static func himaStatuses() async throws -> [AvailabilityEntry] {
        struct Response: Decodable { let statuses: [HimaStatusDTO] }
        let body: Response = try await send(path: "/hima-statuses")
        return body.statuses.map(\.entry)
    }

    /// PUT /hima-statuses/me — 表明する（既存の表明と、それへの誘いは消える）
    static func postHima(message: String, expiresAt: Date) async throws {
        struct Body: Encodable {
            let message: String
            let expiresAt: String
        }
        let _: Empty = try await send(
            path: "/hima-statuses/me", method: "PUT",
            json: Body(message: message, expiresAt: ISODate.string(from: expiresAt))
        )
    }

    /// DELETE /hima-statuses/me
    static func clearHima() async throws {
        let _: Empty = try await send(path: "/hima-statuses/me", method: "DELETE")
    }

    /// GET /hima-statuses/me/invites — 自分の表明に届いた誘い（新しい順）
    static func himaInvites() async throws -> [AvailabilityInvite] {
        struct Response: Decodable { let invites: [HimaInviteDTO] }
        let body: Response = try await send(path: "/hima-statuses/me/invites")
        return body.invites.map(\.invite)
    }

    /// POST /hima-statuses/:id/invites — 誘う
    static func inviteHima(statusId: String, message: String) async throws {
        struct Body: Encodable { let message: String }
        let _: Empty = try await send(
            path: "/hima-statuses/\(statusId)/invites", method: "POST", json: Body(message: message)
        )
    }

    // MARK: - カレンダー招待

    /// GET /invite-directory — 招待先の候補（居住者の名前とメールアドレス）
    static func inviteDirectory() async throws -> [DirectoryUser] {
        struct Entry: Decodable {
            let id: String
            let displayName: String
            let email: String
        }
        struct Response: Decodable { let users: [Entry] }
        let body: Response = try await send(path: "/invite-directory")
        return body.users.map { DirectoryUser(id: $0.id, display_name: $0.displayName, email: $0.email) }
    }

    /// GET /invite-groups
    static func inviteGroups() async throws -> [InviteGroup] {
        struct Response: Decodable { let groups: [InviteGroup] }
        let body: Response = try await send(path: "/invite-groups")
        return body.groups
    }

    /// POST /invite-groups
    static func createInviteGroup(name: String, emails: [String]) async throws -> InviteGroup {
        struct Body: Encodable {
            let name: String
            let emails: [String]
        }
        struct Response: Decodable { let group: InviteGroup }
        let body: Response = try await send(
            path: "/invite-groups", method: "POST", json: Body(name: name, emails: emails)
        )
        return body.group
    }

    /// DELETE /invite-groups/:id
    static func deleteInviteGroup(id: String) async throws {
        let _: Empty = try await send(path: "/invite-groups/\(id)", method: "DELETE")
    }

    // MARK: - カレンダー

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

    /// GET /calendar-events?from=&to=&version= — 共有カレンダーの予定（日本時間の日付。両端を含む）。
    /// サーバーが 15 分ごとに GAS から取り直して D1 に溜めたもの。手元のキャッシュの版を送ると、
    /// 変わっていなければ予定を返さずに `.notModified` になる
    static func calendarEvents(from: String, to: String, version: String?) async throws -> CalendarPage {
        struct Response: Decodable {
            let notModified: Bool
            let version: String
            let events: [CalendarEvent]?
            let hasMore: Bool?
        }
        var query = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        if let version { query.append(URLQueryItem(name: "version", value: version)) }
        let body: Response = try await send(path: "/calendar-events", query: query)
        if body.notModified { return .notModified }
        return .page(version: body.version, events: body.events ?? [], hasMore: body.hasMore ?? false)
    }

    enum CalendarPage {
        /// 送った版が最新（手元のキャッシュをそのまま使ってよい）
        case notModified
        case page(version: String, events: [CalendarEvent], hasMore: Bool)
    }

    /// GET /calendar-events/config — 投稿先カレンダーと ROOM の選択肢（「プライベート」込み）
    static func calendarPostConfig() async throws -> PostConfig {
        struct Response: Decodable { let config: PostConfig }
        let body: Response = try await send(path: "/calendar-events/config")
        return body.config
    }

    struct CalendarEventInput: Encodable {
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

    /// POST /calendar-events — 共有カレンダー（event / house）は GAS 経由、プライベートは本人の Google カレンダーに作る。
    /// プライベートのときだけ本人の Google access token を渡す
    static func createCalendarEvent(_ input: CalendarEventInput, googleAccessToken: String?) async throws -> CalendarEvent {
        struct Body: Encodable {
            let input: CalendarEventInput
            let googleAccessToken: String?

            enum CodingKeys: String, CodingKey { case googleAccessToken }

            func encode(to encoder: Encoder) throws {
                try input.encode(to: encoder)
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(googleAccessToken, forKey: .googleAccessToken)
            }
        }
        struct Response: Decodable { let event: CalendarEvent }
        let body: Response = try await send(
            path: "/calendar-events", method: "POST",
            json: Body(input: input, googleAccessToken: googleAccessToken)
        )
        return body.event
    }

    /// GET /calendar-events/mine — 自分が作ったイベントの ID（MY EVENT 用）
    static func myCalendarEventIds() async throws -> [String] {
        struct Response: Decodable { let eventIds: [String] }
        let body: Response = try await send(path: "/calendar-events/mine")
        return body.eventIds
    }
}
