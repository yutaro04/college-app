import SwiftUI

/// Web 版 `Calendar.tsx` + `BottomNav.tsx` に相当するルート。
/// Laundry / Bathroom は Web 版と同じくリリース時非表示（未完成）のため載せていない。
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    @State private var events = EventsStore()
    @State private var favorites = FavoritesStore()
    @State private var myCreated = MyCreatedEventsStore()
    @State private var selection: Tab = .calendar

    enum Tab: Hashable {
        case calendar, hima, info, settings
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

                InfoScreen()
                    .tabItem { Label("各種情報", systemImage: "info.circle") }
                    .tag(Tab.info)

                SettingsScreen()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }

            ToastView(center: toast)
                .padding(.bottom, 56)
        }
        .task(id: auth.session?.user.id) {
            await myCreated.refresh()
        }
        .onChange(of: auth.authError) { _, newValue in
            if let newValue { toast.show(newValue) }
        }
    }
}
