import Foundation

/// モックモードのインメモリ「サーバー」。
///
/// 状態はアプリ起動中だけメモリに保持する（再起動すると `MockSeed` の初期データに戻る）。
/// レスポンスの形は Supabase PostgREST・Web 版 Next.js API・`services/api/README.md` の API 設計に合わせている。
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
    private var events: [CalendarEvent]
    /// PostgREST のテーブル（availability / availability_invites / invite_groups / created_events）
    private var tables: [String: [[String: Any]]]
    /// 交流機能の状態（`MockBackend+Social.swift`）
    var social = MockSocialState()

    private init() {
        categories = MockSeed.categories
        events = MockSeed.events()
        tables = MockSeed.tables()
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

        if url.host == AppConfig.supabaseURL.host {
            if segments.first == "auth" { return json([String: String]()) }
            if segments.count >= 3, segments[0] == "rest" {
                return postgrest(method: method, table: segments[2], query: query, body: body)
            }
            return notFound()
        }
        if segments.first == "api" {
            return nextAPI(method: method, path: segments, body: body)
        }
        return collegeAPI(method: method, path: segments, query: query, body: body)
    }

    // MARK: - services/api（図鑑・属性・コヒチャ）

    private func collegeAPI(method: String, path: [String], query: [URLQueryItem], body: Data?) -> Reply {
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]

        let (route, param) = Self.match(path, in: Self.collegeRoutes)
        switch (method, route) {
        case ("GET", "health"):
            return json(["ok": true])

        case ("GET", "auth/me"), ("GET", "residents/me"):
            return encode(["resident": resident(myId)!])

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
            return socialAPI(method: method, path: path, query: query, input: input)
        }
    }

    /// 上から順に照合するので、`residents/matches` のような固定パスは `:id` より先に置く
    private static let collegeRoutes = [
        "health", "auth/me", "attribute-categories", "attributes",
        "residents", "residents/matches", "residents/me",
        "residents/me/attributes", "residents/me/attributes/:id", "residents/:id",
        "coffee-chat-requests", "coffee-chat-requests/:id",
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

    // MARK: - Web 版 Next.js API（/api/*）

    private func nextAPI(method: String, path: [String], body: Data?) -> Reply {
        switch (method, path) {
        case ("GET", ["api", "events"]):
            return encode(EventsResponse(success: true, events: events))

        case ("GET", ["api", "events", "config"]):
            return json(["success": true, "config": MockSeed.postConfig])

        case ("POST", ["api", "events", "create"]):
            guard let body, let input = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return json(["success": false, "error": "入力が不正です"])
            }
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
                isAllDay: input["isAllDay"] as? Bool ?? false, color: "#CB1B3B"
            )
            events.append(event)
            tables["created_events", default: []].append(["event_id": event.id, "user_id": myId])
            return encode(EventResponse(success: true, event: event))

        case ("POST", ["api", "auth", "google-token"]):
            return json(["success": true])

        default:
            return notFound()
        }
    }

    private struct EventsResponse: Encodable {
        let success: Bool
        let events: [CalendarEvent]
    }

    private struct EventResponse: Encodable {
        let success: Bool
        let event: CalendarEvent
    }

    // MARK: - Supabase PostgREST（/rest/v1/:table）

    private func postgrest(method: String, table: String, query: [URLQueryItem], body: Data?) -> Reply {
        let filters = query.compactMap { item -> (String, String)? in
            guard let value = item.value, value.hasPrefix("eq.") else { return nil }
            return (item.name, String(value.dropFirst(3)))
        }
        let matches: ([String: Any]) -> Bool = { row in
            filters.allSatisfy { key, value in "\(row[key] ?? "")" == value }
        }

        // profiles は図鑑の居住者から組み立てる
        if table == "profiles" {
            if method == "PATCH", let name = Self.object(body)?["display_name"] as? String {
                for index in residents.indices where matches(["id": residents[index].id]) {
                    residents[index].displayName = name
                }
                return json([String]())
            }
            let rows: [[String: Any]] = residents.map {
                ["id": $0.id, "display_name": $0.displayName, "avatar_url": NSNull(), "email": $0.email]
            }
            return json(rows.filter(matches))
        }

        switch method {
        case "GET":
            var rows = (tables[table] ?? []).filter(matches)
            if table == "availability" {
                rows = rows.filter { (ISODate.parse($0["expires_at"] as? String ?? "") ?? .distantPast) > Date() }
            }
            rows.sort { ($0["created_at"] as? String ?? "") > ($1["created_at"] as? String ?? "") }
            if let limit = query.value("limit").flatMap(Int.init) { rows = Array(rows.prefix(limit)) }
            if query.value("select")?.contains("profiles!") == true {
                let ownerKey = table == "availability_invites" ? "inviter_id" : "user_id"
                rows = rows.map { row in
                    var copy = row
                    let name = residents.first { $0.id == row[ownerKey] as? String }?.displayName
                    copy["profiles"] = ["display_name": name ?? "名無し"]
                    return copy
                }
            }
            return json(rows)

        case "POST":
            guard var row = Self.object(body) else { return error(400, "invalid body") }
            row["id"] = row["id"] ?? UUID().uuidString.lowercased()
            row["created_at"] = row["created_at"] ?? ISODate.string(from: Date())
            if table == "invite_groups" { row.removeValue(forKey: "owner_id") }
            tables[table, default: []].append(row)
            if table == "availability", row["user_id"] as? String == myId {
                scheduleInviteForMe(availabilityId: row["id"] as? String ?? "")
            }
            return json([row], status: 201)

        case "PATCH":
            guard let patch = Self.object(body) else { return error(400, "invalid body") }
            tables[table] = (tables[table] ?? []).map { row in
                matches(row) ? row.merging(patch) { _, new in new } : row
            }
            return json([String]())

        case "DELETE":
            tables[table] = (tables[table] ?? []).filter { !matches($0) }
            if table == "availability" {
                let alive = Set((tables["availability"] ?? []).compactMap { $0["id"] as? String })
                tables["availability_invites"] = (tables["availability_invites"] ?? []).filter {
                    alive.contains($0["availability_id"] as? String ?? "")
                }
            }
            return json([String]())

        default:
            return notFound()
        }
    }

    /// 自分が「ひま」を表明したら、少し後に誰かから誘いが届いたことにする
    /// （ポーリングで新着として検知され、トースト + ローカル通知が出る）
    private func scheduleInviteForMe(availabilityId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            let inviter = MockSeed.himaInviters.randomElement()!
            tables["availability_invites", default: []].append([
                "id": UUID().uuidString.lowercased(),
                "availability_id": availabilityId,
                "availability_user_id": myId,
                "inviter_id": inviter.id,
                "message": inviter.message,
                "created_at": ISODate.string(from: Date()),
            ])
        }
    }

    private static func object(_ body: Data?) -> [String: Any]? {
        guard let body, let value = try? JSONSerialization.jsonObject(with: body) else { return nil }
        if let dict = value as? [String: Any] { return dict }
        return (value as? [[String: Any]])?.first
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
