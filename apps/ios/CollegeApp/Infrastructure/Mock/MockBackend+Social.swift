import Foundation

/// 交流機能のインメモリ状態（`0003_social.sql` のテーブルに対応）
struct MockSocialState {
    struct RecommendationRow {
        let id: String
        let residentId: String
        let name: String
        let genre: Recommendation.Genre
        let area: String?
        let comment: String?
        let url: String?
        let createdAt: String
    }

    struct LikeRow {
        let from: String
        let to: String
        var kind: String
        var topic: String?
        var createdAt: String
    }

    struct WishRow {
        let id: String
        let residentId: String
        let title: String
        let note: String?
        let createdAt: String
    }

    struct WishInvitationRow {
        let id: String
        let wishId: String
        let inviterId: String
        let message: String
        let createdAt: String
    }

    struct SlotRow {
        let id: String
        let residentId: String
        let start: Date
        let end: Date
        let note: String?
    }

    struct GatheringRow {
        let id: String
        let hostId: String
        let title: String
        let location: String?
        let start: Date
        let end: Date
        let capacity: Int?
        let note: String?
        var participantIds: [String]
        var cancelled = false
    }

    struct ThreadRow {
        let id: String
        let starterId: String
        let partnerId: String
        let starterAlias: String
        let partnerAlias: String
        let createdAt: String
        var closedAt: String?
    }

    struct LetterRow {
        let id: String
        let threadId: String
        let senderId: String
        let body: String
        let createdAt: String
        var readAt: String?
    }

    var recommendations: [RecommendationRow] = []
    var likes: [LikeRow] = []
    var wishes: [WishRow] = []
    var wishInvitations: [WishInvitationRow] = []
    var slots: [SlotRow] = []
    var gatherings: [GatheringRow] = []
    var threads: [ThreadRow] = []
    var letters: [LetterRow] = []
}

extension MockBackend {
    /// `residents/me/...` は `residents/:id/...` より先に置く（上から順に照合するため）
    private static let socialRoutes = [
        "recommendations",
        "residents/me/recommendations", "residents/me/recommendations/:id", "residents/:id/recommendations",
        "likes/discover", "likes/matches", "likes/received-count", "likes/:id",
        "invite-wishes", "invite-wishes/invitations", "invite-wishes/:id/invitations",
        "residents/me/invite-wishes", "residents/me/invite-wishes/:id",
        "free-slots", "residents/me/free-slots", "residents/me/free-slots/:id", "residents/:id/free-slots",
        "hima-gatherings", "hima-gatherings/:id", "hima-gatherings/:id/join",
        "pen-pals", "pen-pals/:id", "pen-pals/:id/letters", "pen-pals/:id/report",
    ]

    /// 呼び出し元（`handle`）で lock 済み
    func socialAPI(method: String, path: [String], query: [URLQueryItem], input: [String: Any]) -> Reply {
        let (route, param) = Self.match(path, in: Self.socialRoutes)
        let id = param ?? ""
        let now = Date()
        let nowISO = ISODate.string(from: now)

        switch (method, route) {
        // MARK: おすすめの店
        case ("GET", "recommendations"):
            let genre = query.value("genre")
            let list = social.recommendations
                .filter { genre == nil || $0.genre.rawValue == genre }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap(recommendation)
            return encode(["recommendations": list])

        case ("GET", "residents/:id/recommendations"):
            let list = social.recommendations.filter { $0.residentId == id }.compactMap(recommendation)
            return encode(["recommendations": list])

        case ("POST", "residents/me/recommendations"):
            guard let name = nonEmpty(input["name"]),
                  let genre = (input["genre"] as? String).flatMap(Recommendation.Genre.init)
            else { return error(400, "店名とジャンルを入力してください") }
            let row = MockSocialState.RecommendationRow(
                id: newId("rec"), residentId: myId, name: name, genre: genre,
                area: nonEmpty(input["area"]), comment: nonEmpty(input["comment"]), url: nonEmpty(input["url"]),
                createdAt: nowISO
            )
            social.recommendations.append(row)
            return encode(["recommendation": recommendation(row)!], status: 201)

        case ("DELETE", "residents/me/recommendations/:id"):
            social.recommendations.removeAll { $0.id == id && $0.residentId == myId }
            return json([String: String]())

        // MARK: 気になる
        case ("GET", "likes/discover"):
            let decided = Set(social.likes.filter { $0.from == myId }.map(\.to))
            let mine = Set(residents.first { $0.id == myId }?.attributeIds ?? [])
            let candidates = residents
                .filter { $0.id != myId && !decided.contains($0.id) }
                .map { row in (row, row.attributeIds.filter(mine.contains)) }
                .sorted { $0.1.count > $1.1.count }
                .compactMap { row, shared in
                    resident(row.id).map { ResidentMatch(resident: $0, sharedAttributes: shared.compactMap(attribute)) }
                }
            return encode(["candidates": candidates])

        case ("GET", "likes/matches"):
            return encode(["matches": likeMatches()])

        case ("GET", "likes/received-count"):
            let count = social.likes.filter { $0.to == myId && $0.kind == "like" }.count
            return encode(["count": count])

        case ("PUT", "likes/:id"):
            guard id != myId, ref(id) != nil else { return error(400, "相手が見つかりません") }
            guard let kind = input["kind"] as? String, kind == "like" || kind == "pass" else {
                return error(400, "kind は like か pass です")
            }
            let topic = nonEmpty(input["topic"])
            if let index = social.likes.firstIndex(where: { $0.from == myId && $0.to == id }) {
                social.likes[index].kind = kind
                social.likes[index].topic = topic
                social.likes[index].createdAt = nowISO
            } else {
                social.likes.append(.init(from: myId, to: id, kind: kind, topic: topic, createdAt: nowISO))
            }
            let matched = kind == "like" && social.likes.contains { $0.from == id && $0.to == myId && $0.kind == "like" }
            return encode(["matched": matched])

        // MARK: 〇〇あったら誘って
        case ("GET", "invite-wishes"):
            let residentId = query.value("residentId")
            let list = social.wishes
                .filter { residentId == nil || $0.residentId == residentId }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap(wish)
            return encode(["wishes": list])

        case ("GET", "invite-wishes/invitations"):
            let myWishes = Dictionary(uniqueKeysWithValues: social.wishes.filter { $0.residentId == myId }.map { ($0.id, $0) })
            let list = social.wishInvitations
                .filter { myWishes[$0.wishId] != nil }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap { row in
                    ref(row.inviterId).map {
                        WishInvitation(id: row.id, wishTitle: myWishes[row.wishId]!.title, message: row.message,
                                       createdAt: row.createdAt, inviter: $0)
                    }
                }
            return encode(["invitations": list])

        case ("POST", "invite-wishes/:id/invitations"):
            guard let target = social.wishes.first(where: { $0.id == id }) else { return error(404, "見つかりません") }
            guard target.residentId != myId else { return error(400, "自分の「誘って」には誘えません") }
            social.wishInvitations.append(.init(
                id: newId("winv"), wishId: id, inviterId: myId,
                message: nonEmpty(input["message"]) ?? "誘いたいです！", createdAt: nowISO
            ))
            return json([String: String](), status: 201)

        case ("POST", "residents/me/invite-wishes"):
            guard let title = nonEmpty(input["title"]) else { return error(400, "内容を入力してください") }
            let row = MockSocialState.WishRow(
                id: newId("wish"), residentId: myId, title: title, note: nonEmpty(input["note"]), createdAt: nowISO
            )
            social.wishes.append(row)
            return encode(["wish": wish(row)!], status: 201)

        case ("DELETE", "residents/me/invite-wishes/:id"):
            social.wishes.removeAll { $0.id == id && $0.residentId == myId }
            return json([String: String]())

        // MARK: 空き時間
        case ("GET", "residents/:id/free-slots"):
            let horizon = now.addingTimeInterval(7 * 86400)
            let list = social.slots
                .filter { $0.residentId == id && $0.end > now && $0.start < horizon }
                .sorted { $0.start < $1.start }
                .map { freeSlot($0, withResident: false) }
            return encode(["slots": list])

        case ("GET", "free-slots"):
            let from = query.value("from").flatMap(ISODate.parse)
            let to = query.value("to").flatMap(ISODate.parse)
            let horizon = now.addingTimeInterval(7 * 86400)
            let list = social.slots
                .filter { $0.residentId != myId }
                .filter { slot in
                    if let from, let to { return slot.start <= from && slot.end >= to }
                    return slot.end > now && slot.start < horizon
                }
                .sorted { $0.start < $1.start }
                .map { freeSlot($0, withResident: true) }
            return encode(["slots": list])

        case ("POST", "residents/me/free-slots"):
            guard let start = (input["startsAt"] as? String).flatMap(ISODate.parse),
                  let end = (input["endsAt"] as? String).flatMap(ISODate.parse),
                  end > start
            else { return error(400, "終了は開始より後にしてください") }
            let row = MockSocialState.SlotRow(
                id: newId("slot"), residentId: myId, start: start, end: end, note: nonEmpty(input["note"])
            )
            social.slots.append(row)
            return encode(["slot": freeSlot(row, withResident: false)], status: 201)

        case ("DELETE", "residents/me/free-slots/:id"):
            social.slots.removeAll { $0.id == id && $0.residentId == myId }
            return json([String: String]())

        // MARK: ひま募集
        case ("GET", "hima-gatherings"):
            let list = social.gatherings
                .filter { !$0.cancelled && $0.end > now }
                .sorted { $0.start < $1.start }
                .compactMap(gathering)
            return encode(["gatherings": list])

        case ("POST", "hima-gatherings"):
            guard let title = nonEmpty(input["title"]),
                  let start = (input["startsAt"] as? String).flatMap(ISODate.parse),
                  let end = (input["endsAt"] as? String).flatMap(ISODate.parse),
                  end > start
            else { return error(400, "タイトルと時間を正しく入力してください") }
            let row = MockSocialState.GatheringRow(
                id: newId("gath"), hostId: myId, title: title, location: nonEmpty(input["location"]),
                start: start, end: end, capacity: input["capacity"] as? Int, note: nonEmpty(input["note"]),
                participantIds: []
            )
            social.gatherings.append(row)
            scheduleJoin(gatheringId: row.id)
            return encode(["gathering": gathering(row)!], status: 201)

        case ("DELETE", "hima-gatherings/:id"):
            guard let index = social.gatherings.firstIndex(where: { $0.id == id }) else { return error(404, "見つかりません") }
            guard social.gatherings[index].hostId == myId else { return error(403, "主催者だけが取り消せます") }
            social.gatherings[index].cancelled = true
            return json([String: String]())

        case ("POST", "hima-gatherings/:id/join"), ("DELETE", "hima-gatherings/:id/join"):
            guard let index = social.gatherings.firstIndex(where: { $0.id == id && !$0.cancelled }) else {
                return error(404, "見つかりません")
            }
            var row = social.gatherings[index]
            if method == "POST" {
                guard row.hostId != myId else { return error(400, "主催者は参加者に数えません") }
                if !row.participantIds.contains(myId) {
                    if let capacity = row.capacity, row.participantIds.count >= capacity {
                        return error(409, "定員に達しています")
                    }
                    row.participantIds.append(myId)
                }
            } else {
                row.participantIds.removeAll { $0 == myId }
            }
            social.gatherings[index] = row
            return encode(["gathering": gathering(row)!])

        // MARK: 匿名文通
        case ("GET", "pen-pals"):
            let list = social.threads
                .filter { $0.starterId == myId || $0.partnerId == myId }
                .map(thread)
                .sorted { ($0.lastLetter?.createdAt ?? $0.createdAt) > ($1.lastLetter?.createdAt ?? $1.createdAt) }
            return encode(["threads": list])

        case ("POST", "pen-pals"):
            guard let body = nonEmpty(input["body"]) else { return error(400, "手紙を書いてください") }
            let busy = Set(social.threads.filter { $0.closedAt == nil && ($0.starterId == myId || $0.partnerId == myId) }
                .flatMap { [$0.starterId, $0.partnerId] })
            guard let partner = residents.filter({ $0.id != myId && !busy.contains($0.id) }).randomElement() else {
                return error(409, "いま手紙を受け取れる人がいません")
            }
            let aliases = MockSeed.penNames.shuffled()
            let row = MockSocialState.ThreadRow(
                id: newId("pp"), starterId: myId, partnerId: partner.id,
                starterAlias: aliases[0], partnerAlias: aliases[1], createdAt: nowISO
            )
            social.threads.append(row)
            social.letters.append(.init(id: newId("ltr"), threadId: row.id, senderId: myId, body: body, createdAt: nowISO))
            scheduleReply(threadId: row.id)
            return encode(["thread": thread(row)], status: 201)

        case ("GET", "pen-pals/:id/letters"):
            guard let row = myThread(id) else { return error(404, "見つかりません") }
            for index in social.letters.indices
            where social.letters[index].threadId == row.id && social.letters[index].senderId != myId
                && social.letters[index].readAt == nil {
                social.letters[index].readAt = nowISO
            }
            let list = social.letters.filter { $0.threadId == row.id }.sorted { $0.createdAt < $1.createdAt }.map(letter)
            return encode(["letters": list])

        case ("POST", "pen-pals/:id/letters"):
            guard let row = myThread(id) else { return error(404, "見つかりません") }
            guard row.closedAt == nil else { return error(409, "この文通は終了しています") }
            guard let body = nonEmpty(input["body"]) else { return error(400, "手紙を書いてください") }
            let created = MockSocialState.LetterRow(
                id: newId("ltr"), threadId: row.id, senderId: myId, body: body, createdAt: nowISO
            )
            social.letters.append(created)
            scheduleReply(threadId: row.id)
            return encode(["letter": letter(created)], status: 201)

        case ("PATCH", "pen-pals/:id"):
            guard let index = social.threads.firstIndex(where: { $0.id == id && ($0.starterId == myId || $0.partnerId == myId) })
            else { return error(404, "見つかりません") }
            social.threads[index].closedAt = nowISO
            return json([String: String]())

        case ("POST", "pen-pals/:id/report"):
            guard myThread(id) != nil else { return error(404, "見つかりません") }
            return json([String: String](), status: 201)

        default:
            return notFound()
        }
    }

    // MARK: - 行 → レスポンス

    private func recommendation(_ row: MockSocialState.RecommendationRow) -> Recommendation? {
        ref(row.residentId).map {
            Recommendation(id: row.id, name: row.name, genre: row.genre, area: row.area, comment: row.comment,
                           url: row.url, createdAt: row.createdAt, resident: $0)
        }
    }

    private func wish(_ row: MockSocialState.WishRow) -> InviteWish? {
        ref(row.residentId).map {
            InviteWish(id: row.id, title: row.title, note: row.note, createdAt: row.createdAt, resident: $0)
        }
    }

    private func freeSlot(_ row: MockSocialState.SlotRow, withResident: Bool) -> FreeSlot {
        FreeSlot(id: row.id, startsAt: ISODate.string(from: row.start), endsAt: ISODate.string(from: row.end),
                 note: row.note, resident: withResident ? ref(row.residentId) : nil)
    }

    private func gathering(_ row: MockSocialState.GatheringRow) -> HimaGathering? {
        guard let host = ref(row.hostId) else { return nil }
        return HimaGathering(
            id: row.id, title: row.title, location: row.location,
            startsAt: ISODate.string(from: row.start), endsAt: ISODate.string(from: row.end),
            capacity: row.capacity, note: row.note, host: host, participants: row.participantIds.compactMap(ref)
        )
    }

    private func likeMatches() -> [LikeMatch] {
        social.likes
            .filter { $0.from == myId && $0.kind == "like" }
            .compactMap { mine in
                guard let theirs = social.likes.first(where: { $0.from == mine.to && $0.to == myId && $0.kind == "like" }),
                      let other = ref(mine.to)
                else { return nil }
                return LikeMatch(resident: other, myTopic: mine.topic, theirTopic: theirs.topic,
                                 matchedAt: max(mine.createdAt, theirs.createdAt))
            }
            .sorted { $0.matchedAt > $1.matchedAt }
    }

    private func myThread(_ id: String) -> MockSocialState.ThreadRow? {
        social.threads.first { $0.id == id && ($0.starterId == myId || $0.partnerId == myId) }
    }

    /// 自分から見たスレッド。相手の resident id・名前は含めない
    private func thread(_ row: MockSocialState.ThreadRow) -> PenPalThread {
        let iAmStarter = row.starterId == myId
        let letters = social.letters.filter { $0.threadId == row.id }.sorted { $0.createdAt < $1.createdAt }
        return PenPalThread(
            id: row.id,
            myAlias: iAmStarter ? row.starterAlias : row.partnerAlias,
            partnerAlias: iAmStarter ? row.partnerAlias : row.starterAlias,
            createdAt: row.createdAt, closedAt: row.closedAt,
            lastLetter: letters.last.map(letter),
            unreadCount: letters.filter { $0.senderId != myId && $0.readAt == nil }.count
        )
    }

    private func letter(_ row: MockSocialState.LetterRow) -> PenPalLetter {
        PenPalLetter(id: row.id, fromMe: row.senderId == myId, body: row.body, createdAt: row.createdAt)
    }

    // MARK: - モックならではの自動応答

    /// 文通相手が少し後に返事をくれたことにする
    private func scheduleReply(threadId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            guard let row = social.threads.first(where: { $0.id == threadId }), row.closedAt == nil else { return }
            let partner = row.starterId == myId ? row.partnerId : row.starterId
            social.letters.append(.init(
                id: newId("ltr"), threadId: threadId, senderId: partner,
                body: MockSeed.penPalReplies.randomElement()!, createdAt: ISODate.string(from: Date())
            ))
        }
    }

    /// 自分が立てた募集に、少し後に誰かが参加したことにする
    private func scheduleJoin(gatheringId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            guard let index = social.gatherings.firstIndex(where: { $0.id == gatheringId }),
                  let joiner = residents.filter({ $0.id != self.myId }).randomElement()
            else { return }
            social.gatherings[index].participantIds.append(joiner.id)
        }
    }

    // MARK: - ユーティリティ

    private func nonEmpty(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func newId(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.prefix(8).lowercased())"
    }
}
