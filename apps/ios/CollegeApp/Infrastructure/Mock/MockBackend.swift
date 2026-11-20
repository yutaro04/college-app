import Foundation

/// モックモードのインメモリ「サーバー」。
///
/// 状態はアプリ起動中だけメモリに保持する（再起動すると `MockSeed` の初期データに戻る）。
/// レスポンスの形は `services/api` の実装（未実装分は README の API 設計）に合わせている。
final class MockBackend: @unchecked Sendable {
    static let shared = MockBackend()

    struct Reply {
        let status: Int
        let data: Data
    }

    /// 図鑑の居住者（サーバー側の行に相当）
    struct ResidentRow {
        let id: String
        var displayName: String
        var email: String
        var bio: String?
        var attributeIds: [String]
    }

    let lock = NSLock()

    private let categories: [AttributeCategory]
    private var attributes: [ResidentAttribute] = []
    var residents: [ResidentRow] = []
    private var coffeeChats: [CoffeeChatRequest] = []
    var events: [CalendarEvent]
    /// いまひま・カレンダー招待・MY EVENT（`/hima-statuses` `/invite-groups` `/calendar-events`）
    private var himaStatuses: [MockSeed.HimaStatusRow]
    private var himaInvites: [MockSeed.HimaInviteRow] = []
    private var inviteGroups: [InviteGroup]
    private var createdEventIds: [String] = []
    /// カレンダーの予定の版（予定が変わったときだけ進む。`GET /calendar-events` の version）
    private var calendarVersion = ISODate.string(from: Date())
    /// 交流機能の状態（`MockBackend+Social.swift`）
    var social = MockSocialState()
    /// 日記のイベントクリップの状態（`MockBackend+Events.swift`）
    var eventClips = MockEventClipState()

    private init() {
        categories = MockSeed.categories
        events = MockSeed.events()
        himaStatuses = MockSeed.himaStatuses()
        inviteGroups = MockSeed.inviteGroups
        for seed in MockSeed.residents {
            let ids = seed.attributes.map { findOrCreateAttribute(categoryKey: $0.0, value: $0.1).id }
            residents.append(ResidentRow(
                id: seed.id, displayName: seed.name, email: seed.email, bio: seed.bio, attributeIds: ids
            ))
        }
        social = MockSeed.social(now: Date())
        coffeeChats = MockSeed.coffeeChats.compactMap { seed in
            guard let requester = ref(seed.from), let recipient = ref(seed.to) else { return nil }
            return CoffeeChatRequest(
                id: seed.id, requesterId: seed.from, recipientId: seed.to, status: seed.status,
                message: seed.message, createdAt: MockSeed.iso(minutesAgo: seed.minutesAgo),
                respondedAt: seed.status == .pending ? nil : MockSeed.iso(minutesAgo: seed.minutesAgo / 2),
                requester: requester, recipient: recipient
            )
        }
    }

    var myId: String { MockSeed.myId }

    // MARK: - ルーティング

    func handle(method: String, url: URL, body: Data?) -> Reply {
        lock.lock()
        defer { lock.unlock() }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = comps?.queryItems ?? []
        let segments = url.path.split(separator: "/").map(String.init)

        return collegeAPI(method: method, path: segments, query: query, body: body)
    }

    // MARK: - services/api（図鑑・属性・コヒチャ）

    private func collegeAPI(method: String, path: [String], query: [URLQueryItem], body: Data?) -> Reply {
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]

        let (route, param) = Self.match(path, in: Self.collegeRoutes)
        switch (method, route) {
        case ("GET", "health"):
            return json(["ok": true])

        case ("GET", "calendar-events"):
            if query.value("version") == calendarVersion {
                return json(["notModified": true, "version": calendarVersion])
            }
            let from = query.value("from") ?? "", to = query.value("to") ?? "9999"
            let page = events.filter { $0.dateKey >= from && $0.dateKey <= to }.sorted { $0.startISO < $1.startISO }
            let syncEnd = DateUtil.dateKey(Calendar.current.date(byAdding: .day, value: 60, to: Date())!)
            struct Page: Encodable {
                let notModified = false
                let version: String
                let events: [CalendarEvent]
                let hasMore: Bool
            }
            return encode(Page(version: calendarVersion, events: page, hasMore: to < syncEnd))

        case ("GET", "auth/me"), ("GET", "residents/me"):
            return encode(MeResponse(email: MockSeed.myEmail, resident: resident(myId)!))

        case ("GET", "attribute-categories"):
            return encode(["categories": categories])

        case ("GET", "attributes"):
            let q = normalize(query.value("q") ?? "")
            let key = query.value("categoryKey")
            let hits = attributes
                .filter { key == nil || $0.categoryKey == key }
                .filter { q.isEmpty || normalize($0.value).contains(q) }
            return encode(["attributes": Array(hits.prefix(100))])

        case ("GET", "residents"):
            let q = normalize(query.value("q") ?? "")
            let attributeIds = Set(query.filter { $0.name == "attributeId" }.compactMap(\.value))
            let key = query.value("categoryKey")
            let hits = residents
                .filter { q.isEmpty || normalize($0.displayName).contains(q) || attributesMatch($0, q) }
                .filter { attributeIds.isEmpty || !attributeIds.isDisjoint(with: $0.attributeIds) }
                .filter { key == nil || $0.attributeIds.contains { id in attribute(id)?.categoryKey == key } }
                .compactMap { resident($0.id) }
            return encode(["residents": hits])

        case ("GET", "residents/matches"):
            guard let me = residents.first(where: { $0.id == myId }) else { return notFound() }
            let mine = Set(me.attributeIds)
            let matches = residents
                .filter { $0.id != myId }
                .map { row in (row, row.attributeIds.filter(mine.contains)) }
                .filter { !$0.1.isEmpty }
                .sorted { $0.1.count > $1.1.count }
                .compactMap { row, shared in
                    resident(row.id).map { ResidentMatch(resident: $0, sharedAttributes: shared.compactMap(attribute)) }
                }
            return encode(["matches": matches])

        case ("PATCH", "residents/me"):
            guard let index = residents.firstIndex(where: { $0.id == myId }) else { return notFound() }
            if let name = input["displayName"] as? String, !name.isEmpty { residents[index].displayName = name }
            if let bio = input["bio"] as? String { residents[index].bio = bio }
            return encode(["resident": resident(myId)!])

        case ("GET", "residents/me/attributes"):
            return encode(["attributes": resident(myId)?.attributes ?? []])

        case ("POST", "residents/me/attributes"):
            guard let key = input["categoryKey"] as? String,
                  categories.contains(where: { $0.key == key }),
                  let value = (input["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return error(400, "カテゴリと値を指定してください") }
            let attr = findOrCreateAttribute(categoryKey: key, value: value)
            if let index = residents.firstIndex(where: { $0.id == myId }),
               !residents[index].attributeIds.contains(attr.id) {
                residents[index].attributeIds.append(attr.id)
            }
            return encode(["attribute": attr])

        case ("DELETE", "residents/me/attributes/:id"):
            if let index = residents.firstIndex(where: { $0.id == myId }) {
                residents[index].attributeIds.removeAll { $0 == param }
            }
            return json([String: String]())

        case ("GET", "residents/:id"):
            guard let found = resident(param ?? "") else { return error(404, "居住者が見つかりません") }
            return encode(["resident": found])

        case ("GET", "coffee-chat-requests"):
            let box = query.value("box") ?? "received"
            let status = query.value("status")
            let list = coffeeChats
                .filter { box == "sent" ? $0.requesterId == myId : $0.recipientId == myId }
                .filter { status == nil || $0.status.rawValue == status }
                .sorted { $0.createdAt > $1.createdAt }
            return encode(["requests": list])

        case ("POST", "coffee-chat-requests"):
            guard let recipientId = input["recipientId"] as? String, let recipient = ref(recipientId) else {
                return error(400, "申請先が見つかりません")
            }
            guard recipientId != myId else { return error(400, "自分には申請できません") }
            let duplicated = coffeeChats.contains {
                $0.status == .pending && Set([$0.requesterId, $0.recipientId]) == Set([myId, recipientId])
            }
            guard !duplicated else { return error(409, "すでに返事待ちの申請があります") }
            let message = (input["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let created = CoffeeChatRequest(
                id: "req_\(UUID().uuidString.prefix(8).lowercased())", requesterId: myId, recipientId: recipientId,
                status: .pending, message: message, createdAt: ISODate.string(from: Date()), respondedAt: nil,
                requester: ref(myId)!, recipient: recipient
            )
            coffeeChats.append(created)
            return encode(["request": created], status: 201)

        case ("PATCH", "coffee-chat-requests/:id"):
            guard let index = coffeeChats.firstIndex(where: { $0.id == param }) else {
                return error(404, "申請が見つかりません")
            }
            let request = coffeeChats[index]
            guard request.status == .pending else { return error(409, "この申請はすでに処理済みです") }
            let next: CoffeeChatRequest.Status
            switch input["action"] as? String {
            case "accept" where request.recipientId == myId: next = .accepted
            case "decline" where request.recipientId == myId: next = .declined
            case "cancel" where request.requesterId == myId: next = .cancelled
            default: return error(403, "この操作はできません")
            }
            coffeeChats[index].status = next
            coffeeChats[index].respondedAt = ISODate.string(from: Date())
            return encode(["request": coffeeChats[index]])

        default:
            if path.first == "events" { return eventsAPI(method: method, path: path, query: query, input: input) }
            if let reply = legacyAPI(method: method, route: route, param: param, input: input) { return reply }
            return socialAPI(method: method, path: path, query: query, input: input)
        }
    }

    /// 上から順に照合するので、`residents/matches` のような固定パスは `:id` より先に置く
    private static let collegeRoutes = [
        "health", "auth/me", "attribute-categories", "attributes",
        "residents", "residents/matches", "residents/me",
        "residents/me/attributes", "residents/me/attributes/:id", "residents/:id",
        "coffee-chat-requests", "coffee-chat-requests/:id",
        "hima-statuses", "hima-statuses/me", "hima-statuses/me/invites", "hima-statuses/:id/invites",
        "invite-groups", "invite-groups/:id", "invite-directory",
        "calendar-events", "calendar-events/config", "calendar-events/mine",
    ]

    /// パスをルート定義に照合し、(ルート, `:id` の値) を返す
    static func match(_ path: [String], in routes: [String]) -> (String, String?) {
        for route in routes {
            let template = route.split(separator: "/").map(String.init)
            guard template.count == path.count else { continue }
            var param: String?
            let ok = zip(template, path).allSatisfy { t, p in
                if t == ":id" { param = p; return true }
                return t == p
            }
            if ok { return (route, param) }
        }
        return ("", nil)
    }

    func resident(_ id: String) -> Resident? {
        guard let row = residents.first(where: { $0.id == id }) else { return nil }
        return Resident(
            id: row.id, displayName: row.displayName, avatarUrl: nil, bio: row.bio,
            attributes: row.attributeIds.compactMap(attribute)
        )
    }

    func ref(_ id: String) -> ResidentRef? {
        residents.first { $0.id == id }.map { ResidentRef(id: $0.id, displayName: $0.displayName, avatarUrl: nil) }
    }

    func attribute(_ id: String) -> ResidentAttribute? {
        attributes.first { $0.id == id }
    }

    private func attributesMatch(_ row: ResidentRow, _ q: String) -> Bool {
        row.attributeIds.contains { id in attribute(id).map { normalize($0.value).contains(q) } ?? false }
    }

    /// services/api の `normalized_value` 相当（大文字小文字・前後空白の揺れを吸収）
    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @discardableResult
    private func findOrCreateAttribute(categoryKey: String, value: String) -> ResidentAttribute {
        if let existing = attributes.first(where: {
            $0.categoryKey == categoryKey && normalize($0.value) == normalize(value)
        }) {
            return existing
        }
        let created = ResidentAttribute(id: "attr_\(attributes.count + 1)", categoryKey: categoryKey, value: value)
        attributes.append(created)
        return created
    }

    private struct MeResponse: Encodable {
        let email: String
        let resident: Resident
    }

    // MARK: - いまひま・カレンダー招待・カレンダー（旧 Supabase / Next.js）

    private func legacyAPI(method: String, route: String, param: String?, input: [String: Any]) -> Reply? {
        switch (method, route) {
        case ("GET", "hima-statuses"):
            let now = Date()
            let statuses = himaStatuses.filter { $0.expiresAt > now }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap(himaStatusJSON)
            return json(["statuses": statuses])

        case ("PUT", "hima-statuses/me"):
            guard let expires = ISODate.parse(input["expiresAt"] as? String ?? ""), expires > Date() else {
                return error(400, "期限が不正です")
            }
            clearMyHima()
            let row = MockSeed.HimaStatusRow(
                id: UUID().uuidString.lowercased(), residentId: myId,
                message: input["message"] as? String ?? "", expiresAt: expires, createdAt: Date()
            )
            himaStatuses.append(row)
            scheduleInviteForMe(statusId: row.id)
            return json(["status": himaStatusJSON(row) ?? [:]])

        case ("DELETE", "hima-statuses/me"):
            clearMyHima()
            return Reply(status: 204, data: Data())

        case ("GET", "hima-statuses/me/invites"):
            let mine = Set(himaStatuses.filter { $0.residentId == myId }.map(\.id))
            let invites = himaInvites.filter { mine.contains($0.statusId) }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(50)
                .compactMap { invite -> [String: Any]? in
                    guard let inviter = ref(invite.inviterId) else { return nil }
                    return [
                        "id": invite.id, "inviter": refJSON(inviter), "message": invite.message,
                        "createdAt": ISODate.string(from: invite.createdAt),
                    ]
                }
            return json(["invites": Array(invites)])

        case ("POST", "hima-statuses/:id/invites"):
            guard let status = himaStatuses.first(where: { $0.id == param && $0.expiresAt > Date() }) else {
                return error(404, "この「ひま」はもう終わっています")
            }
            guard status.residentId != myId else { return error(400, "自分には誘えません") }
            let invite = MockSeed.HimaInviteRow(
                id: UUID().uuidString.lowercased(), statusId: status.id, inviterId: myId,
                message: input["message"] as? String ?? "", createdAt: Date()
            )
            himaInvites.append(invite)
            return json(["invite": ["id": invite.id]], status: 201)

        case ("GET", "invite-directory"):
            let users = residents.map { ["id": $0.id, "displayName": $0.displayName, "email": $0.email] }
            return json(["users": users])

        case ("GET", "invite-groups"):
            return encode(["groups": inviteGroups])

        case ("POST", "invite-groups"):
            let group = InviteGroup(
                id: UUID().uuidString.lowercased(),
                name: input["name"] as? String ?? "",
                emails: input["emails"] as? [String] ?? []
            )
            inviteGroups.append(group)
            return encode(["group": group], status: 201)

        case ("DELETE", "invite-groups/:id"):
            inviteGroups.removeAll { $0.id == param }
            return Reply(status: 204, data: Data())

        case ("POST", "calendar-events"):
            let dateKey = input["dateKey"] as? String ?? DateUtil.dateKey(Date())
            let startISO = input["startISO"] as? String ?? ""
            let endISO = input["endISO"] as? String ?? ""
            let calendarKey = input["calendarKey"] as? String ?? "event"
            let event = CalendarEvent(
                id: "evt_\(UUID().uuidString.prefix(8).lowercased())",
                calendarName: MockSeed.calendarName(for: calendarKey),
                title: input["title"] as? String ?? "",
                description: input["description"] as? String ?? "",
                location: input["location"] as? String ?? "",
                startISO: startISO, endISO: endISO, dateKey: dateKey,
                startTime: MockSeed.hhmm(startISO), endTime: MockSeed.hhmm(endISO),
                displayDate: MockSeed.displayDate(dateKey),
                isAllDay: input["isAllDay"] as? Bool ?? false,
                color: calendarKey == "private" ? "#4285F4" : "#CB1B3B"
            )
            events.append(event)
            calendarVersion = ISODate.string(from: Date())
            createdEventIds.append(event.id)
            return encode(["event": event], status: 201)

        case ("GET", "calendar-events/config"):
            return json(["config": MockSeed.postConfig])

        case ("GET", "calendar-events/mine"):
            return json(["eventIds": createdEventIds])

        default:
            return nil
        }
    }

    private func himaStatusJSON(_ row: MockSeed.HimaStatusRow) -> [String: Any]? {
        guard let resident = ref(row.residentId) else { return nil }
        return [
            "id": row.id, "resident": refJSON(resident), "message": row.message,
            "expiresAt": ISODate.string(from: row.expiresAt), "createdAt": ISODate.string(from: row.createdAt),
        ]
    }

    private func refJSON(_ ref: ResidentRef) -> [String: Any] {
        ["id": ref.id, "displayName": ref.displayName, "avatarUrl": ref.avatarUrl ?? NSNull()]
    }

    /// 自分の表明と、それへの誘いを消す（サーバーの ON DELETE CASCADE 相当）
    private func clearMyHima() {
        let mine = Set(himaStatuses.filter { $0.residentId == myId }.map(\.id))
        himaStatuses.removeAll { mine.contains($0.id) }
        himaInvites.removeAll { mine.contains($0.statusId) }
    }

    /// 自分が「ひま」を表明したら、少し後に誰かから誘いが届いたことにする
    /// （ポーリングで新着として検知され、トースト + ローカル通知が出る）
    private func scheduleInviteForMe(statusId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            guard himaStatuses.contains(where: { $0.id == statusId }) else { return }
            let inviter = MockSeed.himaInviters.randomElement()!
            himaInvites.append(MockSeed.HimaInviteRow(
                id: UUID().uuidString.lowercased(), statusId: statusId, inviterId: inviter.id,
                message: inviter.message, createdAt: Date()
            ))
        }
    }

    // MARK: - レスポンス生成

    func encode(_ value: some Encodable, status: Int = 200) -> Reply {
        Reply(status: status, data: (try? JSONEncoder().encode(value)) ?? Data())
    }

    func json(_ value: Any, status: Int = 200) -> Reply {
        Reply(status: status, data: (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
    }

    func error(_ status: Int, _ message: String) -> Reply {
        json(["error": message], status: status)
    }

    func notFound() -> Reply {
        error(404, "Not Found (mock)")
    }
}

extension [URLQueryItem] {
    func value(_ name: String) -> String? {
        first { $0.name == name }?.value
    }
}
