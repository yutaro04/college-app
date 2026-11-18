import SwiftUI

/// 自分の図鑑プロフィール（自己紹介 + 属性タグ）の編集
struct MyDirectoryProfileView: View {
    @Environment(DirectoryStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var bio = ""
    @State private var savingBio = false
    @State private var addingCategory: AttributeCategory?
    @State private var myRecommendations: [Recommendation] = []
    @State private var addingRecommendation = false
    @State private var addingWish = false
    @Environment(RecommendationsStore.self) private var recommendations
    @Environment(InviteWishesStore.self) private var wishes

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自己紹介")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("どんな人か、話しかけてほしい話題など", text: $bio, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.system(size: 14))
                        .textFieldStyle(.roundedBorder)
                    Button(savingBio ? "保存中..." : "保存") {
                        Task { await saveBio() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(savingBio || bio == (store.me?.bio ?? ""))
                    .opacity(bio == (store.me?.bio ?? "") ? 0.4 : 1)
                }
                .cardStyle()

                ForEach(store.categories) { category in
                    categoryCard(category)
                }

                Text("タグは自由に追加できます。同じタグを持つ人が図鑑の「共通点が多い人」に表示されます。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)

                sectionHeader("こんなことあったら誘って", icon: "hand.wave") { addingWish = true }
                ForEach(wishes.mine(myId: store.me?.id)) { wish in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wish.title)
                                .font(.system(size: 14, weight: .semibold))
                            if let note = wish.note {
                                Text(note)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        deleteButton {
                            try await wishes.delete(wish)
                        }
                    }
                    .cardStyle(padding: 14)
                }

                sectionHeader("おすすめの店", icon: "storefront") { addingRecommendation = true }
                ForEach(myRecommendations) { recommendation in
                    RecommendationCard(recommendation: recommendation) {
                        Task {
                            do {
                                try await recommendations.delete(recommendation)
                                myRecommendations.removeAll { $0.id == recommendation.id }
                            } catch {
                                toast.show("削除に失敗しました")
                            }
                        }
                    }
                }

                Label("空き時間は「ひま」タブ >「空き時間」から登録できます", systemImage: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.surface)
        .navigationTitle("図鑑プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.me == nil { await store.load() }
            bio = store.me?.bio ?? ""
            await wishes.load()
            await reloadRecommendations()
        }
        .sheet(isPresented: $addingRecommendation) {
            AddRecommendationSheet { await reloadRecommendations() }
        }
        .sheet(isPresented: $addingWish) { AddInviteWishSheet() }
        .sheet(item: $addingCategory) { category in
            AddAttributeSheet(category: category)
        }
    }

    private func categoryCard(_ category: AttributeCategory) -> some View {
        let tags = store.me?.attributes(in: category.key) ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category.label, systemImage: CategoryStyle.icon(category.key))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    addingCategory = category
                } label: {
                    Label("追加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            if tags.isEmpty {
                Text("未設定")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        Button {
                            Task {
                                do {
                                    try await store.removeMyAttribute(tag)
                                } catch {
                                    toast.show("削除に失敗しました")
                                }
                            }
                        } label: {
                            AttributeChip(attribute: tag, removable: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func reloadRecommendations() async {
        guard let id = store.me?.id else { return }
        myRecommendations = (try? await CollegeAPI.recommendations(residentId: id)) ?? myRecommendations
    }

    private func sectionHeader(_ title: String, icon: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(action: onAdd) {
                Label("追加", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func deleteButton(_ action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                do { try await action() } catch { toast.show("削除に失敗しました") }
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    private func saveBio() async {
        savingBio = true
        defer { savingBio = false }
        do {
            try await store.updateBio(bio)
            toast.show("自己紹介を保存しました")
        } catch {
            toast.show("保存に失敗しました")
        }
    }
}

/// タグ追加シート。既存タグを候補に出しつつ、無ければ新規作成できる（フリータグ）
private struct AddAttributeSheet: View {
    let category: AttributeCategory

    @Environment(DirectoryStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var suggestions: [ResidentAttribute] = []

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var mine: Set<String> { Set(store.me?.attributes.map(\.id) ?? []) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("\(category.label)を入力", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { add(trimmed) }

                if !trimmed.isEmpty, !suggestions.contains(where: { $0.value.lowercased() == trimmed.lowercased() }) {
                    Button {
                        add(trimmed)
                    } label: {
                        Label("「\(trimmed)」を新しいタグとして追加", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                if !suggestions.isEmpty {
                    Text(trimmed.isEmpty ? "みんなが使っているタグ" : "既存のタグ")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions.filter { !mine.contains($0.id) }) { tag in
                            Button {
                                add(tag.value)
                            } label: {
                                AttributeChip(attribute: tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("\(category.label)を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: text) {
            suggestions = await store.suggestAttributes(categoryKey: category.key, q: trimmed)
        }
    }

    private func add(_ value: String) {
        guard !value.isEmpty else { return }
        Task {
            do {
                try await store.addMyAttribute(categoryKey: category.key, value: value)
                toast.show("「\(value)」を追加しました")
                dismiss()
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }
}
