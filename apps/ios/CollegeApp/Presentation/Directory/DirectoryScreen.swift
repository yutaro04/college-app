import SwiftUI

/// カレッジ生図鑑。居住者一覧・タグ絞り込み・共通点の多い人（マッチング）
struct DirectoryScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DirectoryStore.self) private var store

    @State private var showingFilter = false
    @State private var mode: Mode = .initial(.people)

    enum Mode: String, SegmentOption {
        case people, recommendations, wishes

        var label: String {
            switch self {
            case .people: return "みんな"
            case .recommendations: return "おすすめ店"
            case .wishes: return "誘って"
            }
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    LoginView()
                } else if mode == .recommendations {
                    RecommendationsListView()
                } else if mode == .wishes {
                    InviteWishesListView()
                } else if store.loading {
                    LoadingView()
                } else if let error = store.error, store.residents.isEmpty {
                    ErrorRetryView(message: error) { Task { await store.load() } }
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if auth.isSignedIn { SegmentBar(selection: $mode) }
            }
            .background(Theme.surface)
            .navigationTitle("カレッジ生図鑑")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $store.query, prompt: "名前・タグで検索")
            .onSubmit(of: .search) { Task { try? await store.search() } }
            .onChange(of: store.query) { _, new in
                // クリアボタンで空になったときは全件に戻す
                if new.isEmpty { Task { try? await store.search() } }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if mode == .people {
                    Button {
                        showingFilter = true
                    } label: {
                        Image(systemName: store.selectedAttributes.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    }
                }
            }
            .sheet(isPresented: $showingFilter) {
                AttributeFilterSheet()
            }
        }
        .task(id: auth.session?.user.id) {
            guard auth.isSignedIn else { return }
            await store.load()
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !store.selectedAttributes.isEmpty {
                    selectedFilters
                } else if store.query.isEmpty, !store.matches.isEmpty {
                    matchesSection
                }

                Text(store.selectedAttributes.isEmpty && store.query.isEmpty
                     ? "みんな (\(store.residents.count))"
                     : "検索結果 (\(store.residents.count))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)

                if store.residents.isEmpty {
                    Text("該当する人がいません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(store.residents) { resident in
                        NavigationLink {
                            ResidentDetailView(residentId: resident.id)
                        } label: {
                            ResidentRow(resident: resident, myAttributes: Set(store.me?.attributes ?? []), isMe: resident.id == store.me?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("あなたと共通点が多い人")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.matches) { match in
                        NavigationLink {
                            ResidentDetailView(residentId: match.resident.id)
                        } label: {
                            MatchCard(match: match)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -4)
        }
    }

    private var selectedFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("タグで絞り込み中（いずれかに一致）")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("クリア") { Task { await store.clearFilters() } }
                    .font(.system(size: 12, weight: .semibold))
            }
            FlowLayout(spacing: 6) {
                ForEach(store.selectedAttributes) { attribute in
                    Button {
                        Task { await store.toggleFilter(attribute) }
                    } label: {
                        AttributeChip(attribute: attribute, highlighted: true, removable: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 一覧の 1 行
private struct ResidentRow: View {
    let resident: Resident
    let myAttributes: Set<ResidentAttribute>
    let isMe: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ResidentAvatar(id: resident.id, name: resident.displayName, avatarUrl: resident.avatarUrl, size: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(resident.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if isMe {
                        Text("あなた")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.primaryLight, in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                if let affiliation = resident.affiliation {
                    Text(affiliation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                FlowLayout(spacing: 4) {
                    ForEach(resident.attributes.filter { $0.categoryKey != "university" && $0.categoryKey != "company" }.prefix(5)) { attribute in
                        AttributeChip(attribute: attribute, highlighted: !isMe && myAttributes.contains(attribute))
                    }
                }
            }
        }
        .cardStyle(padding: 14)
    }
}

/// 「共通点が多い人」の横スクロールカード
private struct MatchCard: View {
    let match: ResidentMatch

    var body: some View {
        VStack(spacing: 8) {
            ResidentAvatar(id: match.resident.id, name: match.resident.displayName, avatarUrl: match.resident.avatarUrl, size: 56)
            Text(match.resident.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("共通点 \(match.sharedAttributes.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text(match.sharedAttributes.prefix(2).map(\.value).joined(separator: "・"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 120)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 2, x: 0, y: 1)
    }
}

/// カテゴリ別に、図鑑に登場するタグを選んで絞り込むシート
private struct AttributeFilterSheet: View {
    @Environment(DirectoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var all: [ResidentAttribute] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(store.categories) { category in
                        let tags = all.filter { $0.categoryKey == category.key }
                        if !tags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(category.label, systemImage: CategoryStyle.icon(category.key))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(tags) { tag in
                                        Button {
                                            Task { await store.toggleFilter(tag) }
                                        } label: {
                                            AttributeChip(attribute: tag, highlighted: store.selectedAttributes.contains(tag))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("タグで絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("クリア") { Task { await store.clearFilters() } }
                        .disabled(store.selectedAttributes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            all = await store.suggestAttributes(categoryKey: nil, q: "")
        }
    }
}
