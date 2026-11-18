import Foundation

// 交流機能のドメインモデル。JSON の形は services/api/README.md の API 設計に合わせている。

// MARK: - おすすめの店

struct Recommendation: Codable, Identifiable, Hashable {
    enum Genre: String, Codable, CaseIterable, Identifiable {
        case cafe, restaurant, bar, shop, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cafe: return "カフェ"
            case .restaurant: return "ごはん"
            case .bar: return "バー・居酒屋"
            case .shop: return "ショップ"
            case .other: return "その他"
            }
        }

        var icon: String {
            switch self {
            case .cafe: return "cup.and.saucer.fill"
            case .restaurant: return "fork.knife"
            case .bar: return "wineglass.fill"
            case .shop: return "bag.fill"
            case .other: return "mappin.and.ellipse"
            }
        }
    }

    let id: String
    let name: String
    let genre: Genre
    let area: String?
    let comment: String?
    let url: String?
    let createdAt: String
    /// 投稿者
    let resident: ResidentRef
}

// MARK: - 気になる（マチアプ風）

struct LikeMatch: Codable, Identifiable, Hashable {
    let resident: ResidentRef
    /// 自分が相手のどこに興味を持ったか
    let myTopic: String?
    /// 相手が自分のどこに興味を持ったか
    let theirTopic: String?
    let matchedAt: String

    var id: String { resident.id }
}

// MARK: - 〇〇あったら誘って

struct InviteWish: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let note: String?
    let createdAt: String
    let resident: ResidentRef
}

/// 自分の「誘って」に届いた誘い
struct WishInvitation: Codable, Identifiable, Hashable {
    let id: String
    let wishTitle: String
    let message: String
    let createdAt: String
    let inviter: ResidentRef
}

// MARK: - 空き時間・ひま募集

struct FreeSlot: Codable, Identifiable, Hashable {
    let id: String
    let startsAt: String
    let endsAt: String
    let note: String?
    /// `GET /free-slots` のように複数人分を返すときだけ入る
    let resident: ResidentRef?

    var start: Date? { ISODate.parse(startsAt) }
    var end: Date? { ISODate.parse(endsAt) }
}

struct HimaGathering: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let location: String?
    let startsAt: String
    let endsAt: String
    let capacity: Int?
    let note: String?
    let host: ResidentRef
    var participants: [ResidentRef]

    var isFull: Bool { capacity.map { participants.count >= $0 } ?? false }
}

// MARK: - 匿名文通

/// 相手の正体（resident id・名前）は API が返さない。ペンネームだけで表示する
struct PenPalThread: Codable, Identifiable, Hashable {
    let id: String
    let myAlias: String
    let partnerAlias: String
    let createdAt: String
    var closedAt: String?
    var lastLetter: PenPalLetter?
    var unreadCount: Int
}

struct PenPalLetter: Codable, Identifiable, Hashable {
    let id: String
    let fromMe: Bool
    let body: String
    let createdAt: String
}
