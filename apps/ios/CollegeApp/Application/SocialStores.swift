import Foundation
import Observation

/// おすすめの店（みんなの一覧 + 自分の登録）
@MainActor
@Observable
final class RecommendationsStore {
    private(set) var all: [Recommendation] = []
    private(set) var loading = true
    private(set) var error: String?
    var genre: Recommendation.Genre?

    func load() async {
        error = nil
        do {
            all = try await CollegeAPI.recommendations(genre: genre)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func add(_ input: CollegeAPI.NewRecommendation) async throws {
        let created = try await CollegeAPI.addRecommendation(input)
        if genre == nil || genre == created.genre { all.insert(created, at: 0) }
    }

    func delete(_ recommendation: Recommendation) async throws {
        try await CollegeAPI.deleteRecommendation(id: recommendation.id)
        all.removeAll { $0.id == recommendation.id }
    }
}

/// 気になる（マチアプ風のカード + 相互マッチ）
@MainActor
@Observable
final class LikesStore {
    private(set) var candidates: [ResidentMatch] = []
    private(set) var matches: [LikeMatch] = []
    private(set) var receivedCount = 0
    private(set) var loading = true
    private(set) var error: String?

    func load() async {
        error = nil
        do {
            async let candidates = CollegeAPI.discover()
            async let matches = CollegeAPI.likeMatches()
            async let count = CollegeAPI.receivedLikeCount()
            self.candidates = try await candidates
            self.matches = try await matches
            self.receivedCount = try await count
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// 「気になる」を送る。マッチが成立したら相手を返す
    func like(_ candidate: ResidentMatch, topic: String?) async throws -> LikeMatch? {
        let matched = try await CollegeAPI.like(residentId: candidate.id, kind: "like", topic: topic)
        candidates.removeAll { $0.id == candidate.id }
        guard matched else { return nil }
        matches = (try? await CollegeAPI.likeMatches()) ?? matches
        return matches.first { $0.id == candidate.id }
    }

    func pass(_ candidate: ResidentMatch) async throws {
        _ = try await CollegeAPI.like(residentId: candidate.id, kind: "pass", topic: nil)
        candidates.removeAll { $0.id == candidate.id }
    }
}

/// 「〇〇あったら誘って」
@MainActor
@Observable
final class InviteWishesStore {
    private(set) var wishes: [InviteWish] = []
    private(set) var receivedInvitations: [WishInvitation] = []
    private(set) var loading = true
    private(set) var error: String?

    func load() async {
        error = nil
        do {
            async let wishes = CollegeAPI.inviteWishes()
            async let invitations = CollegeAPI.receivedWishInvitations()
            self.wishes = try await wishes
            self.receivedInvitations = try await invitations
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func mine(myId: String?) -> [InviteWish] { wishes.filter { $0.resident.id == myId } }

    func add(title: String, note: String) async throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = try await CollegeAPI.addInviteWish(title: title, note: trimmed.isEmpty ? nil : trimmed)
        wishes.insert(created, at: 0)
    }

    func delete(_ wish: InviteWish) async throws {
        try await CollegeAPI.deleteInviteWish(id: wish.id)
        wishes.removeAll { $0.id == wish.id }
    }

    func invite(_ wish: InviteWish, message: String) async throws {
        try await CollegeAPI.inviteForWish(id: wish.id, message: message)
    }
}

/// 空き時間とひま募集
@MainActor
@Observable
final class HimaPlanStore {
    private(set) var gatherings: [HimaGathering] = []
    /// みんなの空き時間（今後 7 日間）
    private(set) var everyonesSlots: [FreeSlot] = []
    private(set) var mySlots: [FreeSlot] = []
    private(set) var loading = true
    private(set) var error: String?

    func load(myId: String?) async {
        error = nil
        do {
            async let gatherings = CollegeAPI.himaGatherings()
            async let everyone = CollegeAPI.everyonesFreeSlots()
            self.gatherings = try await gatherings
            self.everyonesSlots = try await everyone
            if let myId { mySlots = try await CollegeAPI.freeSlots(residentId: myId) }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// その時間帯をまるごと空けている人
    func freeResidents(from: Date, to: Date) async -> [FreeSlot] {
        (try? await CollegeAPI.everyonesFreeSlots(from: from, to: to)) ?? []
    }

    func create(_ input: CollegeAPI.NewGathering) async throws {
        let created = try await CollegeAPI.createHimaGathering(input)
        gatherings.append(created)
        gatherings.sort { $0.startsAt < $1.startsAt }
    }

    func cancel(_ gathering: HimaGathering) async throws {
        try await CollegeAPI.cancelHimaGathering(id: gathering.id)
        gatherings.removeAll { $0.id == gathering.id }
    }

    func setJoined(_ gathering: HimaGathering, joined: Bool) async throws {
        let updated = try await CollegeAPI.setJoined(gatheringId: gathering.id, joined: joined)
        if let index = gatherings.firstIndex(where: { $0.id == updated.id }) { gatherings[index] = updated }
    }

    func addSlot(start: Date, end: Date, note: String) async throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = try await CollegeAPI.addFreeSlot(start: start, end: end, note: trimmed.isEmpty ? nil : trimmed)
        mySlots.append(created)
        mySlots.sort { $0.startsAt < $1.startsAt }
    }

    func deleteSlot(_ slot: FreeSlot) async throws {
        try await CollegeAPI.deleteFreeSlot(id: slot.id)
        mySlots.removeAll { $0.id == slot.id }
    }
}

/// 匿名文通
@MainActor
@Observable
final class PenPalStore {
    private(set) var threads: [PenPalThread] = []
    private(set) var loading = true
    private(set) var error: String?

    var unreadCount: Int { threads.reduce(0) { $0 + $1.unreadCount } }

    func load() async {
        error = nil
        do {
            threads = try await CollegeAPI.penPalThreads()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func start(letter: String) async throws {
        let created = try await CollegeAPI.startPenPal(body: letter)
        threads.insert(created, at: 0)
    }

    func letters(threadId: String) async throws -> [PenPalLetter] {
        let letters = try await CollegeAPI.penPalLetters(threadId: threadId)
        // 取得したら既読になるので一覧側の未読数も消す
        if let index = threads.firstIndex(where: { $0.id == threadId }) { threads[index].unreadCount = 0 }
        return letters
    }

    func send(threadId: String, body: String) async throws -> PenPalLetter {
        let letter = try await CollegeAPI.sendPenPalLetter(threadId: threadId, body: body)
        if let index = threads.firstIndex(where: { $0.id == threadId }) { threads[index].lastLetter = letter }
        return letter
    }

    func close(threadId: String) async throws {
        try await CollegeAPI.closePenPal(threadId: threadId)
        if let index = threads.firstIndex(where: { $0.id == threadId }) {
            threads[index].closedAt = ISODate.string(from: Date())
        }
    }

    func report(threadId: String, reason: String) async throws {
        try await CollegeAPI.reportPenPal(threadId: threadId, reason: reason)
    }
}
