import SwiftUI

/// Web 版 `SettingsView.tsx` + `ProfileView.tsx` の移植。
/// 通知設定は Web 版でも未完成扱いで非表示なので、ここでも載せていない。
struct SettingsScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    ProfileForm()
                } else {
                    LoginView()
                }
            }
            .background(Theme.surface)
            .navigationTitle(auth.isSignedIn ? "プロフィール" : "設定")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct ProfileForm: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    @State private var name = ""
    @State private var saving = false
    @State private var showSignOutConfirm = false

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !saving && !trimmed.isEmpty && trimmed != auth.profile?.display_name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("メールアドレス")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Text(auth.user?.email ?? "-")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    Text("ユーザー名")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)

                    TextField("ユーザー名", text: $name)
                        .font(.system(size: 14))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, new in
                            if new.count > 40 { name = String(new.prefix(40)) }
                        }

                    Button(saving ? "保存中..." : "保存") {
                        Task { await save() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(canSave ? 1 : 0.4)
                    .disabled(!canSave)
                    .buttonStyle(.plain)
                }
                .cardStyle()

                Button("ログアウト") { showSignOutConfirm = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .onAppear { name = auth.profile?.display_name ?? "" }
        .onChange(of: auth.profile?.display_name) { _, new in
            if let new, name.isEmpty { name = new }
        }
        .confirmationDialog("ログアウトしますか？", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await auth.updateDisplayName(name)
            toast.show("名前を変更しました")
        } catch {
            toast.show("変更に失敗しました")
        }
    }
}
