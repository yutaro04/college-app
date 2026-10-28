import Observation
import SwiftUI

/// Web 版 `Toast.tsx` の移植。2 秒で自動的に消える。
@MainActor
@Observable
final class ToastCenter {
    private(set) var message = ""
    private(set) var visible = false

    private var hideTask: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        visible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.visible = false
        }
    }
}

struct ToastView: View {
    let center: ToastCenter

    var body: some View {
        Text(center.message)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(.label).opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(center.visible ? 1 : 0)
            .offset(y: center.visible ? 0 : 48)
            .animation(.easeOut(duration: 0.3), value: center.visible)
            .allowsHitTesting(false)
            .padding(.bottom, 24)
    }
}

/// 読み込み中のスピナー（Web 版の animate-spin 相当）
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.primary)
            Text("読み込み中...")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// エラー + 再試行
struct ErrorRetryView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("再試行", action: onRetry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 折りたたみ用の矢印（Web 版の chevron + rotate-180）
struct DisclosureChevron: View {
    let isOpen: Bool
    var color: Color = Theme.textTertiary

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .animation(.easeOut(duration: 0.25), value: isOpen)
    }
}