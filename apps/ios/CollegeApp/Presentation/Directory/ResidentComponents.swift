import SwiftUI

/// 顔写真がまだ無い居住者向けの、イニシャル入りの丸アイコン
struct ResidentAvatar: View {
    let id: String
    let name: String
    var avatarUrl: String? = nil
    var size: CGFloat = 44

    private static let palette: [Color] = [
        Color(hex: "#CB1B3B")!, Color(hex: "#3B82F6")!, Color(hex: "#10B981")!,
        Color(hex: "#F59E0B")!, Color(hex: "#8B5CF6")!, Color(hex: "#EC4899")!, Color(hex: "#0EA5E9")!,
    ]

    private var color: Color {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        Group {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(color.opacity(0.15))
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

extension ResidentRef {
    func avatar(size: CGFloat) -> ResidentAvatar {
        ResidentAvatar(id: id, name: displayName, avatarUrl: avatarUrl, size: size)
    }
}

extension Resident {
    var ref: ResidentRef { ResidentRef(id: id, displayName: displayName, avatarUrl: avatarUrl) }

    /// 一覧で名前の下に出す「所属」（大学 or 会社）
    var affiliation: String? {
        (attributes(in: "university") + attributes(in: "company")).map(\.value).first
    }
}

/// 属性カテゴリごとの色とアイコン
enum CategoryStyle {
    static func color(_ key: String) -> Color {
        switch key {
        case "hobby": return Color(hex: "#F59E0B")!
        case "interest": return Color(hex: "#8B5CF6")!
        case "specialty": return Color(hex: "#3B82F6")!
        case "university": return Color(hex: "#10B981")!
        case "company": return Color(hex: "#64748B")!
        default: return Theme.primary
        }
    }

    static func icon(_ key: String) -> String {
        switch key {
        case "hobby": return "heart"
        case "interest": return "sparkles"
        case "specialty": return "lightbulb"
        case "university": return "building.columns"
        case "company": return "briefcase"
        default: return "tag"
        }
    }
}

/// 属性タグのチップ
struct AttributeChip: View {
    let attribute: ResidentAttribute
    var highlighted = false
    var removable = false

    var body: some View {
        let color = CategoryStyle.color(attribute.categoryKey)
        HStack(spacing: 4) {
            Image(systemName: CategoryStyle.icon(attribute.categoryKey))
                .font(.system(size: 9, weight: .semibold))
            Text(attribute.value)
                .font(.system(size: 12, weight: highlighted ? .bold : .medium))
            if removable {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(highlighted ? .white : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(highlighted ? color : color.opacity(0.12), in: Capsule())
    }
}
