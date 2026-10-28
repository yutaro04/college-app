import Foundation

/// 「ひま」の表明（public.availability）
struct AvailabilityEntry: Identifiable, Hashable {
    let id: String
    let user_id: String
    let display_name: String
    let message: String
    let expires_at: String
    let created_at: String
}

/// 「誘う」（public.availability_invites）
struct AvailabilityInvite: Identifiable, Hashable {
    let id: String
    let inviter_id: String
    let inviter_name: String
    let message: String
    let created_at: String
}

// MARK: - PostgREST の生レスポンス
//
// `profiles!fk(display_name)` の埋め込みは、1:1 の関連でもオブジェクトではなく
// 配列で返ってくることがあるため、どちらでもデコードできるようにしている。

struct EmbeddedName: Decodable, Hashable {
    let display_name: String?

    /// `{"display_name": "..."}` と `[{"display_name": "..."}]` の両方を受け付ける
    static func first(from container: EmbeddedNameContainer?) -> String? {
        container?.value?.display_name
    }
}

struct EmbeddedNameContainer: Decodable, Hashable {
    let value: EmbeddedName?

    init(from decoder: Decoder) throws {
        let single = try? EmbeddedName(from: decoder)
        if let single, single.display_name != nil {
            value = single
            return
        }
        let many = try? [EmbeddedName](from: decoder)
        value = many?.first
    }
}

struct AvailabilityRow: Decodable {
    let id: String
    let user_id: String
    let message: String
    let expires_at: String
    let created_at: String
    let profiles: EmbeddedNameContainer?

    var entry: AvailabilityEntry {
        AvailabilityEntry(
            id: id,
            user_id: user_id,
            display_name: EmbeddedName.first(from: profiles) ?? "名無し",
            message: message,
            expires_at: expires_at,
            created_at: created_at
        )
    }
}

struct InviteRow: Decodable {
    let id: String
    let inviter_id: String
    let message: String
    let created_at: String
    let profiles: EmbeddedNameContainer?

    var invite: AvailabilityInvite {
        AvailabilityInvite(
            id: id,
            inviter_id: inviter_id,
            inviter_name: EmbeddedName.first(from: profiles) ?? "名無し",
            message: message,
            created_at: created_at
        )
    }
}
