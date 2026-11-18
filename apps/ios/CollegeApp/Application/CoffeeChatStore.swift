import Foundation
import Observation

/// コーヒーチャット（1on1）申請の送受信
@MainActor
@Observable
final class CoffeeChatStore {
    private(set) var received: [CoffeeChatRequest] = []
    private(set) var sent: [CoffeeChatRequest] = []
    private(set) var loading = true
    private(set) var error: String?

    var pendingReceivedCount: Int { received.filter { $0.status == .pending }.count }

    /// 相手との間に返事待ちの申請があるか（同一ペアの pending は API 側で重複禁止）
    func pendingRequest(with residentId: String) -> CoffeeChatRequest? {
        (sent + received).first {
            $0.status == .pending && ($0.recipientId == residentId || $0.requesterId == residentId)
        }
    }

    func load() async {
        error = nil
        do {
            async let received = CollegeAPI.coffeeChatRequests(box: .received)
            async let sent = CollegeAPI.coffeeChatRequests(box: .sent)
            self.received = try await received
            self.sent = try await sent
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func send(to residentId: String, message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = try await CollegeAPI.createCoffeeChatRequest(
            recipientId: residentId, message: trimmed.isEmpty ? nil : trimmed
        )
        sent.insert(created, at: 0)
    }

    func respond(_ request: CoffeeChatRequest, action: CoffeeChatRequest.Action) async throws {
        let updated = try await CollegeAPI.respondCoffeeChatRequest(id: request.id, action: action)
        if let index = received.firstIndex(where: { $0.id == updated.id }) { received[index] = updated }
        if let index = sent.firstIndex(where: { $0.id == updated.id }) { sent[index] = updated }
    }
}
