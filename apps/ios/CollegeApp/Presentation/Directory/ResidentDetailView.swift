import SwiftUI

/// 図鑑の個人ページ。プロフィール・属性・コーヒーチャット申請
struct ResidentDetailView: View {
    let residentId: String

    @Environment(DirectoryStore.self) private var directory
    @Environment(CoffeeChatStore.self) private var coffeeChat
    @Environment(ToastCenter.self) private var toast

    @State private var resident: Resident?
    @State private var error: String?
    @State private var composing = false
    @State private var recommendations: [Recommendation] = []
    @State private var wishes: [InviteWish] = []
    @State private var freeSlots: [FreeSlot] = []
    @State private var inviting: InviteWish?
    @Environment(LikesStore.self) private var likes

    private var isMe: Bool { residentId == directory.me?.id }
    private var myAttributes: Set<ResidentAttribute> { Set(directory.me?.attributes ?? []) }

    var body: some View {
        Group {
            if let resident {
                content(resident)
            } else if let error {
                ErrorRetryView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .background(Theme.surface)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .toolbar {
            if !isMe, resident != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await sendLike() }
                    } label: {
                        Label("気になる", systemImage: "heart")
                    }
                }
            }
        }
        .sheet(item: $inviting) { WishInviteSheet(wish: $0) }
        .sheet(isPresented: $composing) {
            if let resident {
                CoffeeChatComposeSheet(recipient: resident.ref) { message in
                    do {
                        try await coffeeChat.send(to: resident.id, message: message)
                        toast.show("コーヒーチャットを申請しました")
                        return true
                    } catch {
                        toast.show(error.localizedDescription)
                        return false
                    }
                }
            }
        }
    }

    private func load() async {
        error = nil
        do {
            async let resident = directory.resident(id: residentId)
            async let recommendations = CollegeAPI.recommendations(residentId: residentId)
            async let wishes = CollegeAPI.inviteWishes(residentId: residentId)
            async let freeSlots = CollegeAPI.freeSlots(residentId: residentId)
            self.resident = try await resident
            // 付随情報は取れなくても個人ページ自体は表示する
            self.recommendations = (try? await recommendations) ?? []
            self.wishes = (try? await wishes) ?? []
            self.freeSlots = (try? await freeSlots) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendLike() async {
        do {
            let matched = try await CollegeAPI.like(residentId: residentId, kind: "like", topic: nil)
            toast.show(matched ? "マッチしました！交流タブの「気になる」で確認できます" : "「気になる」を送りました。相手も気になったらマッチします")
            await likes.load()
        } catch {
            toast.show(error.localizedDescription)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }

    private func content(_ resident: Resident) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    ResidentAvatar(id: resident.id, name: resident.displayName, avatarUrl: resident.avatarUrl, size: 96)
                    Text(resident.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let affiliation = resident.affiliation {
                        Text(affiliation)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                if !isMe { coffeeChatButton(resident) }

                if let bio = resident.bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自己紹介")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                        Text(bio)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cardStyle()
                }

                if !isMe {
                    let shared = resident.attributes.filter(myAttributes.contains)
                    if !shared.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("あなたとの共通点 (\(shared.count))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                            FlowLayout(spacing: 6) {
                                ForEach(shared) { AttributeChip(attribute: $0, highlighted: true) }
                            }
                        }
                        .cardStyle()
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(directory.categories) { category in
                        let tags = resident.attributes(in: category.key)
                        if !tags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(category.label, systemImage: CategoryStyle.icon(category.key))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(tags) { AttributeChip(attribute: $0) }
                                }
                            }
                        }
                    }
                }
                .cardStyle()

                if !wishes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("こんなことあったら誘って", icon: "hand.wave")
                            .padding(.horizontal, 4)
                        ForEach(wishes) { wish in
                            WishCard(wish: wish, isMine: isMe, showsOwner: false) { inviting = wish }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("空いている時間", icon: "calendar.badge.clock")
                    FreeSlotWeekView(slots: freeSlots)
                }
                .cardStyle()

                if !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("おすすめの店", icon: "storefront")
                            .padding(.horizontal, 4)
                        ForEach(recommendations) { RecommendationCard(recommendation: $0) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func coffeeChatButton(_ resident: Resident) -> some View {
        if let pending = coffeeChat.pendingRequest(with: resident.id) {
            Label(
                pending.requesterId == resident.id ? "相手から申請が届いています（コヒチャタブ）" : "申請済み・返事待ち",
                systemImage: "clock"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button {
                composing = true
            } label: {
                Label("コーヒーチャットに誘う", systemImage: "cup.and.saucer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

/// コーヒーチャット申請の入力シート
struct CoffeeChatComposeSheet: View {
    let recipient: ResidentRef
    /// 送信に成功したら true を返す
    let onSend: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sending = false

    private let presets = ["お茶しながらお話ししませんか？", "研究/仕事の話を聞かせてください！", "共通の趣味の話をしましょう"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    recipient.avatar(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(recipient.displayName)さんに")
                            .font(.system(size: 15, weight: .semibold))
                        Text("1on1 のコーヒーチャットを申請します")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                TextField("ひとことメッセージ（任意）", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                FlowLayout(spacing: 6) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) { message = preset }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.primaryLight.opacity(0.6), in: Capsule())
                            .foregroundStyle(Theme.primary)
                            .buttonStyle(.plain)
                    }
                }

                Text("日程や場所は、承諾されたあと直接やり取りして決めてください。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                Button {
                    Task {
                        sending = true
                        if await onSend(message) { dismiss() }
                        sending = false
                    }
                } label: {
                    Text(sending ? "送信中..." : "申請する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending)
            }
            .padding(16)
            .background(Theme.surface)
            .navigationTitle("コーヒーチャット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
