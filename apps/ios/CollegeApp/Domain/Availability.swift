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
