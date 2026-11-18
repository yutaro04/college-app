import SwiftUI

@main
struct CollegeAppApp: App {
    @State private var auth = AuthStore.shared
    @State private var toast = ToastCenter()

    init() {
        if AppConfig.useMockAPI { MockURLProtocol.install() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(toast)
                .tint(Theme.primary)
                .task { await auth.restore() }
        }
    }
}