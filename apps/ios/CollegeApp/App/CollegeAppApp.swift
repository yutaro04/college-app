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
            // アプリ全体がログイン必須。一度ログインすればキーチェーンから復元されるので、以後この画面は出ない
            Group {
                if auth.loading {
                    ProgressView()
                } else if auth.isSignedIn {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environment(auth)
            .environment(toast)
            .tint(Theme.primary)
            .task { await auth.restore() }
        }
    }
}