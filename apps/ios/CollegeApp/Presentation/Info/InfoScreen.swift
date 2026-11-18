import SwiftUI

/// Web 版 `InfoView.tsx` の移植。本文中の URL はタップできるリンクにする。
struct InfoScreen: View {
    @State private var openTitle: String?

    /// 設定タブの NavigationStack 内に push して表示する
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(CollegeInfo.sections) { section in
                    sectionCard(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.surface)
        .navigationTitle("各種情報")
        .navigationBarTitleDisplayMode(.large)
    }

    private func sectionCard(_ section: InfoSection) -> some View {
        let isOpen = openTitle == section.title
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    openTitle = isOpen ? nil : section.title
                }
            } label: {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    DisclosureChevron(isOpen: isOpen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(linkified(section.body))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .tint(Theme.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 2, y: 1)
    }

    /// Web 版の `linkify()` 相当。本文中の http(s) URL だけを AttributedString のリンクにする。
    private func linkified(_ text: String) -> AttributedString {
        let nsText = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = (detector?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [])
            .filter { match in
                guard let scheme = match.url?.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }

        var result = AttributedString()
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result += AttributedString(plain)
            }
            var link = AttributedString(nsText.substring(with: match.range))
            link.link = match.url
            link.underlineStyle = .single
            result += link
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            result += AttributedString(nsText.substring(from: cursor))
        }
        return result
    }
}
