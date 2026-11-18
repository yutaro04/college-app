import Foundation

/// コーヒーチャット（1on1）申請
struct CoffeeChatRequest: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case pending, accepted, declined, cancelled

        var label: String {
            switch self {
            case .pending: return "返事待ち"
            case .accepted: return "承諾"
            case .declined: return "見送り"
            case .cancelled: return "取り消し"
            }
        }
    }

    enum Action: String, Encodable {
        case accept, decline, cancel
    }

    let id: String
    let requesterId: String
    let recipientId: String
    var status: Status
    let message: String?
    let createdAt: String
    var respondedAt: String?
    let requester: ResidentRef
    let recipient: ResidentRef

    /// 自分から見た相手
    func counterpart(myId: String) -> ResidentRef {
        requesterId == myId ? recipient : requester
    }
}
