import SwiftUI

/// Web 版 `Calendar.tsx` のカレンダー画面部分 + `TabBar.tsx` + `Timeline.tsx`。
struct CalendarScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    let events: EventsStore
    let favorites: FavoritesStore
    let myCreated: MyCreatedEventsStore

    @State private var tab: EventTab = .all
    @State private var refreshing = false
    @State private var showAddEvent = false

    enum EventTab: String, CaseIterable, Identifiable {
        case all, myCreated, myEvents
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "ALL EVENTS"
            case .myCreated: return "MY EVENT"
            case .myEvents: return "FAVORITE"
            }
        }

        var emptyMessage: String {
            switch self {
            case .all: return "予定はありません"
            case .myCreated: return "作成した予定はありません"
            case .myEvents: return "お気に入りの予定はありません"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.surface.ignoresSafeArea()

            if events.loading {
                LoadingView()
            } else if let error = events.error, events.events.isEmpty {
                ErrorRetryView(message: error) { Task { await reload() } }
            } else {
                list
                addButton
            }
        }
        // 開くたびに呼ぶが、前回の確認から 15 分以内ならサーバーには問い合わせない
        .task { await events.load() }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet { created in
                events.addLocalEvent(created)
                myCreated.add(created.id)
                favorites.add(created.id)
                toast.show("イベントを追加しました")
            }
        }
    }

    // MARK: - リスト

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                FeaturedHeader(
                    events: events.events,
                    favorites: favorites,
                    refreshing: refreshing,
                    topInset: SafeArea.top,
                    onRefresh: { Task { await reload() } }
                )

                VStack(spacing: 0) {
                    tabBar
                        .padding(.bottom, 16)
                    timeline
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 96)
            }
        }
        .ignoresSafeArea(edges: .top)
        .refreshable { await events.refresh() }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(EventTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.label)
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(tab == item ? Theme.primary : Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.card)
                                    .shadow(color: Theme.cardShadow, radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var timeline: some View {
        let groups = groupedEvents()
        if groups.isEmpty {
            Text(tab.emptyMessage)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
            loadMoreFooter
        } else {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.dateKey) { group in
                    Section {
                        ForEach(group.events, id: \.rowKey) { event in
                            EventRow(
                                event: event,
                                isFavorite: favorites.isFavorite(event.id),
                                onToggleFavorite: { toggleFavorite(event.id) }
                            )
                            .padding(.bottom, 12)
                        }
                    } header: {
                        DateSectionHeader(dateKey: group.dateKey, todayKey: todayKey)
                    }
                }
                // LazyVStack の中に置くので、一番下までスクロールして見えたときに次の 30 日を読む
                loadMoreFooter
            }
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if events.hasMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                // 読み終わると loadedTo が変わるので、まだ見えていればもう一度読む
                .task(id: events.loadedTo) { await events.loadMore() }
        }
    }

    private var addButton: some View {
        Button {
            guard auth.isSignedIn else {
                toast.show("ログインが必要です")
                Task { await auth.signInWithGoogle() }
                return
            }
            showAddEvent = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(0.4), radius: 6, y: 4)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("イベントを追加")
    }

    // MARK: - ロジック（Web 版 Timeline.tsx と同じ）

    private var todayKey: String { DateUtil.dateKey(Date()) }

    /// 終了時刻が現在より後のイベントのみ（終日イベントは当日中なら表示）→ タブで絞り込み → 日付ごとにグループ化
    private func groupedEvents() -> [(dateKey: String, events: [CalendarEvent])] {
        let now = Date()
        let today = todayKey

        let upcoming = events.events.filter { event in
            if event.isAllDay { return event.dateKey >= today }
            guard let end = event.endDate else { return false }
            return end > now
        }

        let filtered: [CalendarEvent]
        switch tab {
        case .all: filtered = upcoming
        case .myCreated: filtered = upcoming.filter { myCreated.isMine($0.id) }
        case .myEvents: filtered = upcoming.filter { favorites.isFavorite($0.id) }
        }

        return Dictionary(grouping: filtered, by: \.dateKey)
            .sorted { $0.key < $1.key }
            .map { (dateKey: $0.key, events: $0.value.sorted { $0.startISO < $1.startISO }) }
    }

    private func toggleFavorite(_ id: String) {
        let added = favorites.toggle(id)
        toast.show(added ? "お気に入り追加" : "お気に入り解除")
    }

    private func reload() async {
        refreshing = true
        await events.refresh()
        refreshing = false
        toast.show("同期完了")
    }
}

/// Web 版の sticky な日付ヘッダー
struct DateSectionHeader: View {
    let dateKey: String
    let todayKey: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(month)/\(day)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)

            Text("（\(AppConstants.dayNames[weekdayIndex])）")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(weekdayColor)

            if let relative {
                Text(relative)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.primaryLight, in: Capsule())
            }

            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private var parts: [Int] { dateKey.split(separator: "-").compactMap { Int($0) } }
    private var month: Int { parts.count == 3 ? parts[1] : 0 }
    private var day: Int { parts.count == 3 ? parts[2] : 0 }

    /// Calendar.component(.weekday) は 1=日曜なので 0 始まりに直す
    private var weekdayIndex: Int {
        guard let date = DateUtil.date(fromKey: dateKey) else { return 0 }
        return Calendar.current.component(.weekday, from: date) - 1
    }

    /// 日曜=赤・土曜=青
    private var weekdayColor: Color {
        switch weekdayIndex {
        case 0: return Theme.primary
        case 6: return .blue
        default: return Theme.textTertiary
        }
    }

    private var relative: String? {
        if dateKey == todayKey { return "今日" }
        guard let today = DateUtil.date(fromKey: todayKey),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        else { return nil }
        return dateKey == DateUtil.dateKey(tomorrow) ? "明日" : nil
    }
}

/// ScrollView を safe area いっぱいに広げたうえで、ヘッダーだけ上部インセット分ずらすためのヘルパー
enum SafeArea {
    @MainActor
    static var top: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 47
    }
}
