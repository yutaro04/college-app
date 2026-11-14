import Foundation

/// public.profiles
struct Profile: Codable, Identifiable, Hashable {
    let id: String
    var display_name: String
    var avatar_url: String?
}

/// 招待先の予測変換用（Web 版 `useUserDirectory`）
struct DirectoryUser: Codable, Identifiable, Hashable {
    let id: String
    let display_name: String
    let email: String
}

/// public.invite_groups（Web 版 `useInviteGroups`）
struct InviteGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let emails: [String]
}

/// 招待候補（登録ユーザー / メーリングリスト / 自由入力）
struct InviteSuggestion: Identifiable, Hashable {
    let label: String
    let email: String
    var id: String { email }
}
