import SwiftUI
import UIKit

/// Web 版 globals.css のカラートークンを SwiftUI に移植したもの。
enum Theme {
    /// --color-primary: #CB1B3B
    static let primary = Color(red: 0.796, green: 0.106, blue: 0.231)
    /// --color-primary-light: #f0d0d7
    static let primaryLight = Color(red: 0.941, green: 0.816, blue: 0.843)
    /// --color-surface: #fafafa
    static let surface = Color(.systemGroupedBackground)
    /// カード背景（Web 版の bg-white 相当。ダークモードでも破綻しないようシステム色を使う）
    static let card = Color(.secondarySystemGroupedBackground)

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let cardCornerRadius: CGFloat = 16
    static let cardShadow = Color.black.opacity(0.06)
}

extension View {
    /// Web 版の `bg-white rounded-2xl shadow-[0_1px_3px_rgba(0,0,0,0.06)]` 相当
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 2, x: 0, y: 1)
    }
}

/// `#RRGGBB` 形式の文字列から Color を作る（イベントの color カラム用）
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
