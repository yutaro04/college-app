import SwiftUI

/// Web 版 `LoginScreen.tsx` の移植。
struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @State private var signingIn = false

    var body: some View {
        VStack(spacing: 24) {
            Text("COLLEGE APP")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("ゆる募やプロフィール機能を使うには\nログインが必要です")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let authError = auth.authError {
                Text(authError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                Task {
                    signingIn = true
                    await auth.signInWithGoogle()
                    signingIn = false
                }
            } label: {
                HStack(spacing: 12) {
                    GoogleMark()
                    Text(signingIn ? "ログイン中..." : "Googleでログイン")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                .shadow(color: Theme.cardShadow, radius: 2, y: 1)
            }
            .disabled(signingIn)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Google の 4 色マーク
private struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(Color(red: 0.918, green: 0.263, blue: 0.208), lineWidth: 4)
            Circle()
                .trim(from: 0.25, to: 0.5)
                .stroke(Color(red: 0.984, green: 0.737, blue: 0.020), lineWidth: 4)
            Circle()
                .trim(from: 0.5, to: 0.75)
                .stroke(Color(red: 0.204, green: 0.659, blue: 0.325), lineWidth: 4)
            Circle()
                .trim(from: 0.75, to: 1.0)
                .stroke(Color(red: 0.259, green: 0.522, blue: 0.957), lineWidth: 4)
        }
        .rotationEffect(.degrees(-45))
        .frame(width: 18, height: 18)
    }
}
