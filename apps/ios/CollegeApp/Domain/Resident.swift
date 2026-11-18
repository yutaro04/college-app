import Foundation

/// カレッジ生図鑑の居住者（services/api の `Resident` + 属性一覧）
struct Resident: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var avatarUrl: String?
    var bio: String?
    var attributes: [ResidentAttribute]

    func attributes(in categoryKey: String) -> [ResidentAttribute] {
        attributes.filter { $0.categoryKey == categoryKey }
    }
}

/// 申請一覧などに埋め込まれる居住者の最小情報
struct ResidentRef: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let avatarUrl: String?
}

/// 属性カテゴリ（趣味 / 興味 / 専門分野 / 大学 / 会社）
struct AttributeCategory: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let label: String
    let sortOrder: Int
}

/// 属性タグ。ユーザーが自由に追加できるフリータグ
struct ResidentAttribute: Codable, Identifiable, Hashable {
    let id: String
    let categoryKey: String
    let value: String
}

/// `GET /residents/matches` の 1 件。自分と共有している属性つき
struct ResidentMatch: Codable, Identifiable, Hashable {
    let resident: Resident
    let sharedAttributes: [ResidentAttribute]

    var id: String { resident.id }
}
