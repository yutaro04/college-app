import SwiftUI

// MARK: - おすすめの店

/// みんなのおすすめの店
struct RecommendationsListView: View {
    @Environment(RecommendationsStore.self) private var store

    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        genreChip(nil, label: "すべて", icon: "square.grid.2x2")
                        ForEach(Recommendation.Genre.allCases) { genre in
                            genreChip(genre, label: genre.label, icon: genre.icon)
                        }
                    }
                }

                Button {
                    adding = true
                } label: {
                    Label("おすすめの店を教える", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                if store.all.isEmpty, !store.loading {
                    Text("まだおすすめがありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                ForEach(store.all) { recommendation in
                    RecommendationCard(recommendation: recommendation, showsPoster: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .sheet(isPresented: $adding) { AddRecommendationSheet() }
    }

    private func genreChip(_ genre: Recommendation.Genre?, label: String, icon: String) -> some View {
        let selected = store.genre == genre
        return Button {
            store.genre = genre
            Task { await store.load() }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Theme.primary : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    var showsPoster = false
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recommendation.genre.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primaryLight.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text([recommendation.genre.label, recommendation.area].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let comment = recommendation.comment {
                Text(comment)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let urlString = recommendation.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("リンクを開く", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            if showsPoster {
                NavigationLink {
                    ResidentDetailView(residentId: recommendation.resident.id)
                } label: {
                    HStack(spacing: 6) {
                        recommendation.resident.avatar(size: 20)
                        Text("\(recommendation.resident.displayName)さんのおすすめ")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 14)
    }
}

struct AddRecommendationSheet: View {
    @Environment(RecommendationsStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    /// 追加後に呼ぶ（図鑑プロフィール編集画面で自分の一覧を取り直す用）
    var onAdded: (() async -> Void)?

    @State private var name = ""
    @State private var genre: Recommendation.Genre = .cafe
    @State private var area = ""
    @State private var comment = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("店名", text: $name)
                Picker("ジャンル", selection: $genre) {
                    ForEach(Recommendation.Genre.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                TextField("エリア（例: 下北沢 南口）", text: $area)
                TextField("おすすめポイント", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
                TextField("URL（任意）", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("おすすめの店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { Task { await submit() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func submit() async {
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        do {
            try await store.add(.init(
                name: name.trimmingCharacters(in: .whitespaces), genre: genre,
                area: optional(area), comment: optional(comment), url: optional(url)
            ))
            await onAdded?()
            toast.show("おすすめを追加しました")
            dismiss()
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

// MARK: - 〇〇あったら誘って

/// 「〇〇あったら誘って」掲示板
struct InviteWishesListView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(InviteWishesStore.self) private var store

    @State private var adding = false
    @State private var inviting: InviteWish?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !store.receivedInvitations.isEmpty {
                    receivedCard
                }

                Button {
                    adding = true
                } label: {
                    Label("「〇〇あったら誘って」を出す", systemImage: "hand.wave.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                ForEach(store.wishes) { wish in
                    WishCard(wish: wish, isMine: wish.resident.id == auth.user?.id) {
                        inviting = wish
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .sheet(isPresented: $adding) { AddInviteWishSheet() }
        .sheet(item: $inviting) { WishInviteSheet(wish: $0) }
    }

    private var receivedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("あなたへの誘い (\(store.receivedInvitations.count))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            ForEach(store.receivedInvitations) { invitation in
                NavigationLink {
                    ResidentDetailView(residentId: invitation.inviter.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        invitation.inviter.avatar(size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(invitation.inviter.displayName)さん ·「\(invitation.wishTitle)」")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(invitation.message)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                            Text(DateUtil.relativePast(invitation.createdAt))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }
}

struct WishCard: View {
    let wish: InviteWish
    let isMine: Bool
    var showsOwner = true
    let onInvite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsOwner {
                NavigationLink {
                    ResidentDetailView(residentId: wish.resident.id)
                } label: {
                    wish.resident.avatar(size: 40)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                if showsOwner {
                    Text(isMine ? "あなた" : wish.resident.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(wish.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let note = wish.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if !isMine {
                Button("誘う", action: onInvite)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.primary, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 14)
    }
}

struct AddInviteWishSheet: View {
    @Environment(InviteWishesStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""

    private let presets = ["銭湯行くなら誘って", "飲みに行くなら誘って", "映画行くなら誘って", "ご飯作るなら誘って", "散歩するなら誘って"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: 銭湯行くなら誘って", text: $title)
                    TextField("ひとこと（任意）例: 平日の夜ならOK", text: $note)
                }
                Section("よく使われる例") {
                    FlowLayout(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button(preset) { title = preset }
                                .font(.system(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.primaryLight.opacity(0.6), in: Capsule())
                                .foregroundStyle(Theme.primary)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("誘ってほしいこと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task {
                            do {
                                try await store.add(title: title.trimmingCharacters(in: .whitespaces), note: note)
                                toast.show("追加しました")
                                dismiss()
                            } catch {
                                toast.show(error.localizedDescription)
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct WishInviteSheet: View {
    let wish: InviteWish

    @Environment(InviteWishesStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    wish.resident.avatar(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(wish.resident.displayName)さんを誘う")
                            .font(.system(size: 15, weight: .semibold))
                        Text("「\(wish.title)」")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                TextField("いつ・どこで・何をするか", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Button {
                    Task {
                        sending = true
                        defer { sending = false }
                        do {
                            try await store.invite(wish, message: message)
                            toast.show("誘いを送りました")
                            dismiss()
                        } catch {
                            toast.show(error.localizedDescription)
                        }
                    }
                } label: {
                    Text(sending ? "送信中..." : "誘う")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending || message.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(Theme.surface)
            .navigationTitle("誘う")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
