import Foundation

/// 交流機能（おすすめの店・気になる・誘って・空き時間・ひま募集・匿名文通）のエンドポイント
extension CollegeAPI {

    // MARK: - おすすめの店

    /// GET /recommendations?genre=
    static func recommendations(genre: Recommendation.Genre? = nil) async throws -> [Recommendation] {
        struct Response: Decodable { let recommendations: [Recommendation] }
        let query = genre.map { [URLQueryItem(name: "genre", value: $0.rawValue)] } ?? []
        let body: Response = try await send(path: "/recommendations", query: query)
        return body.recommendations
    }

    /// GET /residents/:id/recommendations
    static func recommendations(residentId: String) async throws -> [Recommendation] {
        struct Response: Decodable { let recommendations: [Recommendation] }
        let body: Response = try await send(path: "/residents/\(residentId)/recommendations")
        return body.recommendations
    }

    struct NewRecommendation: Encodable {
        var name: String
        var genre: Recommendation.Genre
        var area: String?
        var comment: String?
        var url: String?
    }

    /// POST /residents/me/recommendations
    static func addRecommendation(_ input: NewRecommendation) async throws -> Recommendation {
        struct Response: Decodable { let recommendation: Recommendation }
        let body: Response = try await send(path: "/residents/me/recommendations", method: "POST", json: input)
        return body.recommendation
    }

    /// DELETE /residents/me/recommendations/:id
    static func deleteRecommendation(id: String) async throws {
        let _: Empty = try await send(path: "/residents/me/recommendations/\(id)", method: "DELETE")
    }

    // MARK: - 気になる

    /// GET /likes/discover — まだ振り分けていない人（共通点の多い順）
    static func discover() async throws -> [ResidentMatch] {
        struct Response: Decodable { let candidates: [ResidentMatch] }
        let body: Response = try await send(path: "/likes/discover")
        return body.candidates
    }

    /// GET /likes/matches
    static func likeMatches() async throws -> [LikeMatch] {
        struct Response: Decodable { let matches: [LikeMatch] }
        let body: Response = try await send(path: "/likes/matches")
        return body.matches
    }

    /// GET /likes/received-count
    static func receivedLikeCount() async throws -> Int {
        struct Response: Decodable { let count: Int }
        let body: Response = try await send(path: "/likes/received-count")
        return body.count
    }

    /// PUT /likes/:residentId — マッチが成立したら true
    static func like(residentId: String, kind: String, topic: String?) async throws -> Bool {
        struct Body: Encodable {
            let kind: String
            let topic: String?
        }
        struct Response: Decodable { let matched: Bool }
        let body: Response = try await send(
            path: "/likes/\(residentId)", method: "PUT", json: Body(kind: kind, topic: topic)
        )
        return body.matched
    }

    // MARK: - 〇〇あったら誘って

    /// GET /invite-wishes?residentId=
    static func inviteWishes(residentId: String? = nil) async throws -> [InviteWish] {
        struct Response: Decodable { let wishes: [InviteWish] }
        let query = residentId.map { [URLQueryItem(name: "residentId", value: $0)] } ?? []
        let body: Response = try await send(path: "/invite-wishes", query: query)
        return body.wishes
    }

    /// POST /residents/me/invite-wishes
    static func addInviteWish(title: String, note: String?) async throws -> InviteWish {
        struct Body: Encodable {
            let title: String
            let note: String?
        }
        struct Response: Decodable { let wish: InviteWish }
        let body: Response = try await send(
            path: "/residents/me/invite-wishes", method: "POST", json: Body(title: title, note: note)
        )
        return body.wish
    }

    /// DELETE /residents/me/invite-wishes/:id
    static func deleteInviteWish(id: String) async throws {
        let _: Empty = try await send(path: "/residents/me/invite-wishes/\(id)", method: "DELETE")
    }

    /// POST /invite-wishes/:id/invitations
    static func inviteForWish(id: String, message: String) async throws {
        struct Body: Encodable { let message: String }
        let _: Empty = try await send(
            path: "/invite-wishes/\(id)/invitations", method: "POST", json: Body(message: message)
        )
    }

    /// GET /invite-wishes/invitations — 自分の「誘って」に届いた誘い
    static func receivedWishInvitations() async throws -> [WishInvitation] {
        struct Response: Decodable { let invitations: [WishInvitation] }
        let body: Response = try await send(path: "/invite-wishes/invitations")
        return body.invitations
    }

    // MARK: - 空き時間

    /// GET /residents/:id/free-slots
    static func freeSlots(residentId: String) async throws -> [FreeSlot] {
        struct Response: Decodable { let slots: [FreeSlot] }
        let body: Response = try await send(path: "/residents/\(residentId)/free-slots")
        return body.slots
    }

    /// GET /free-slots?from=&to= — 期間を指定すると、その時間帯をまるごと空けている人だけ返す
    static func everyonesFreeSlots(from: Date? = nil, to: Date? = nil) async throws -> [FreeSlot] {
        struct Response: Decodable { let slots: [FreeSlot] }
        var query: [URLQueryItem] = []
        if let from, let to {
            query = [
                URLQueryItem(name: "from", value: ISODate.string(from: from)),
                URLQueryItem(name: "to", value: ISODate.string(from: to)),
            ]
        }
        let body: Response = try await send(path: "/free-slots", query: query)
        return body.slots
    }

    /// POST /residents/me/free-slots
    static func addFreeSlot(start: Date, end: Date, note: String?) async throws -> FreeSlot {
        struct Body: Encodable {
            let startsAt: String
            let endsAt: String
            let note: String?
        }
        struct Response: Decodable { let slot: FreeSlot }
        let body: Response = try await send(
            path: "/residents/me/free-slots", method: "POST",
            json: Body(startsAt: ISODate.string(from: start), endsAt: ISODate.string(from: end), note: note)
        )
        return body.slot
    }

    /// DELETE /residents/me/free-slots/:id
    static func deleteFreeSlot(id: String) async throws {
        let _: Empty = try await send(path: "/residents/me/free-slots/\(id)", method: "DELETE")
    }

    // MARK: - ひま募集

    /// GET /hima-gatherings
    static func himaGatherings() async throws -> [HimaGathering] {
        struct Response: Decodable { let gatherings: [HimaGathering] }
        let body: Response = try await send(path: "/hima-gatherings")
        return body.gatherings
    }

    struct NewGathering: Encodable {
        var title: String
        var location: String?
        var startsAt: String
        var endsAt: String
        var capacity: Int?
        var note: String?
    }

    /// POST /hima-gatherings
    static func createHimaGathering(_ input: NewGathering) async throws -> HimaGathering {
        struct Response: Decodable { let gathering: HimaGathering }
        let body: Response = try await send(path: "/hima-gatherings", method: "POST", json: input)
        return body.gathering
    }

    /// DELETE /hima-gatherings/:id
    static func cancelHimaGathering(id: String) async throws {
        let _: Empty = try await send(path: "/hima-gatherings/\(id)", method: "DELETE")
    }

    /// POST / DELETE /hima-gatherings/:id/join
    static func setJoined(gatheringId: String, joined: Bool) async throws -> HimaGathering {
        struct Response: Decodable { let gathering: HimaGathering }
        let body: Response = try await send(
            path: "/hima-gatherings/\(gatheringId)/join", method: joined ? "POST" : "DELETE"
        )
        return body.gathering
    }

    // MARK: - 匿名文通

    /// GET /pen-pals
    static func penPalThreads() async throws -> [PenPalThread] {
        struct Response: Decodable { let threads: [PenPalThread] }
        let body: Response = try await send(path: "/pen-pals")
        return body.threads
    }

    /// POST /pen-pals — 誰かに最初の手紙を出す（相手はサーバーがランダムに選ぶ）
    static func startPenPal(body letter: String) async throws -> PenPalThread {
        struct Body: Encodable { let body: String }
        struct Response: Decodable { let thread: PenPalThread }
        let body: Response = try await send(path: "/pen-pals", method: "POST", json: Body(body: letter))
        return body.thread
    }

    /// GET /pen-pals/:id/letters
    static func penPalLetters(threadId: String) async throws -> [PenPalLetter] {
        struct Response: Decodable { let letters: [PenPalLetter] }
        let body: Response = try await send(path: "/pen-pals/\(threadId)/letters")
        return body.letters
    }

    /// POST /pen-pals/:id/letters
    static func sendPenPalLetter(threadId: String, body letter: String) async throws -> PenPalLetter {
        struct Body: Encodable { let body: String }
        struct Response: Decodable { let letter: PenPalLetter }
        let body: Response = try await send(
            path: "/pen-pals/\(threadId)/letters", method: "POST", json: Body(body: letter)
        )
        return body.letter
    }

    /// PATCH /pen-pals/:id {action: "close"}
    static func closePenPal(threadId: String) async throws {
        struct Body: Encodable { let action = "close" }
        let _: Empty = try await send(path: "/pen-pals/\(threadId)", method: "PATCH", json: Body())
    }

    /// POST /pen-pals/:id/report
    static func reportPenPal(threadId: String, reason: String) async throws {
        struct Body: Encodable { let reason: String }
        let _: Empty = try await send(
            path: "/pen-pals/\(threadId)/report", method: "POST", json: Body(reason: reason)
        )
    }
}
