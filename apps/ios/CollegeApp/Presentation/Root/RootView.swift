import SwiftUI

/// Web 版 `Calendar.tsx` + `BottomNav.tsx` に相当するルート。
/// Laundry / Bathroom は Web 版と同じくリリース時非表示（未完成）のため載せていない。
/// 図鑑・交流・日記のタブを追加したため、「各種情報」は Settings 内のリンクに移し、
/// Settings 自体は日記タブ右上の歯車から開くシートにした。
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    @State private var events = EventsStore()
    @State private var favorites = FavoritesStore()
    @State private var myCreated = MyCreatedEventsStore()
    @State private var directory = DirectoryStore()
    @State private var coffeeChat = CoffeeChatStore()
    @State private var recommendations = RecommendationsStore()
    @State private var likes = LikesStore()
    @State private var inviteWishes = InviteWishesStore()
    @State private var himaPlan = HimaPlanStore()
    @State private var penPal = PenPalStore()
    @State private var diary = DiaryStore()
    @State private var eventClips = EventClipsStore()
    /// 起動引数 `-InitialTab directory` などで最初に開くタブを指定できる（スクリーンショット確認用）
    @State private var selection: Tab = UserDefaults.standard.string(forKey: "InitialTab").flatMap(Tab.init) ?? .calendar

    enum Tab: String, Hashable {
        case calendar, hima, directory, connect, diary
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                CalendarScreen(events: events, favorites: favorites, myCreated: myCreated)
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(Tab.calendar)

                HimaScreen()
                    .tabItem { Label("ひま", systemImage: "bubble.left.and.bubble.right") }
                    .tag(Tab.hima)

                DirectoryScreen()
                    .tabItem { Label("図鑑", systemImage: "person.2.crop.square.stack") }
                    .tag(Tab.directory)

                ConnectScreen()
                    .tabItem { Label("交流", systemImage: "cup.and.saucer") }
                    .badge(coffeeChat.pendingReceivedCount + penPal.unreadCount)
                    .tag(Tab.connect)

                DiaryScreen()
                    .tabItem { Label("日記", systemImage: "film.stack") }
                    .tag(Tab.diary)
            }
            .environment(directory)
            .environment(coffeeChat)
            .environment(recommendations)
            .environment(likes)
            .environment(inviteWishes)
            .environment(himaPlan)
            .environment(penPal)
            .environment(diary)
            .environment(eventClips)
            .environment(events)

            ToastView(center: toast)
                .padding(.bottom, 56)
        }
        .task(id: auth.session?.user.id) {
            await myCreated.refresh()
            // バッジ表示のため、コヒチャタブを開く前に申請一覧を取っておく
            if auth.isSignedIn {
                await coffeeChat.load()
                await penPal.load()
            }
        }
        .onChange(of: auth.authError) { _, newValue in
            if let newValue { toast.show(newValue) }
        }
    }
}
