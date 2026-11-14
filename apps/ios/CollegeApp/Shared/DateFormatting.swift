import Foundation

/// Web 版 `src/lib/constants.ts`
enum AppConstants {
    static let dayNames = ["日", "月", "火", "水", "木", "金", "土"]
    static let dayNamesEN = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    static let monthNamesEN = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
}

/// ISO8601 文字列 ⇄ Date。
/// Supabase は秒以下 6 桁、Google / スプレッドシートは 0〜3 桁と揺れるため、どちらも受け付ける。
enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        if let d = withFraction.date(from: iso) { return d }
        if let d = plain.date(from: iso) { return d }
        // 秒以下が 4 桁以上あると ISO8601DateFormatter が失敗するので 3 桁に丸めて再試行
        if let trimmed = trimFraction(iso) {
            return withFraction.date(from: trimmed) ?? plain.date(from: trimmed)
        }
        return nil
    }

    static func string(from date: Date) -> String { withFraction.string(from: date) }

    private static func trimFraction(_ iso: String) -> String? {
        guard let dot = iso.firstIndex(of: ".") else { return nil }
        let afterDot = iso.index(after: dot)
        guard let endOfDigits = iso[afterDot...].firstIndex(where: { !$0.isNumber }) else { return nil }
        let digits = iso[afterDot..<endOfDigits]
        guard digits.count > 3 else { return nil }
        let keep = digits.prefix(3)
        return String(iso[..<afterDot]) + keep + String(iso[endOfDigits...])
    }
}

/// Web 版 `src/lib/utils.ts` の移植
enum DateUtil {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// yyyy-MM-dd 形式の日付キーを生成
    static func dateKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// yyyy-MM-dd をローカル時刻の 0:00 として Date に戻す
    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// yyyy-MM-dd + HH:mm（ローカル時刻）→ UTC ISO 文字列
    static func iso(dateKey: String, time: String) -> String {
        let d = parts(dateKey)
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2,
              let date = calendar.date(from: DateComponents(
                  year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
        else { return "" }
        return ISODate.string(from: date)
    }

    private static func parts(_ key: String) -> [Int] { key.split(separator: "-").compactMap { Int($0) } }

    /// 残り時間を簡潔に表示（日/時間/分）
    static func timeUntil(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "開催中" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let mins = (total % 3600) / 60
        if days > 0 { return "あと\(days)日\(hours > 0 ? "\(hours)時間" : "")" }
        if hours > 0 { return "あと\(hours)時間\(mins)分" }
        return "あと\(mins)分"
    }

    /// 「あとX分」（有効期限の表示用）
    static func relativeFuture(_ iso: String) -> String {
        guard let date = ISODate.parse(iso) else { return "" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "期限切れ" }
        let min = Int(diff) / 60
        if min < 60 { return "あと\(min)分" }
        let hr = min / 60
        if hr < 24 { return "あと\(hr)時間" }
        return "あと\(hr / 24)日"
    }

    /// 「X分前」（受信した誘いの表示用）
    static func relativePast(_ iso: String) -> String {
        guard let date = ISODate.parse(iso) else { return "" }
        let diff = -date.timeIntervalSinceNow
        let min = Int(diff) / 60
        if min < 1 { return "たった今" }
        if min < 60 { return "\(min)分前" }
        let hr = min / 60
        if hr < 24 { return "\(hr)時間前" }
        return "\(hr / 24)日前"
    }

    /// 「10/27 14:30」形式
    static func shortDateTime(_ iso: String) -> String {
        guard let date = ISODate.parse(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.setLocalizedDateFormatFromTemplate("Mdjmm")
        return f.string(from: date)
    }

    /// タイトルの【】内に「全員」「新入生」が含まれるか
    static func isMandatoryEvent(_ title: String) -> Bool {
        bracketLabels(title).contains { $0.contains("全員") || $0.contains("新入生") }
    }

    /// タイトルの【】内のテキストをすべて抽出
    static func bracketLabels(_ title: String) -> [String] {
        var labels: [String] = []
        var rest = Substring(title)
        while let open = rest.firstIndex(of: "【"),
              let close = rest[rest.index(after: open)...].firstIndex(of: "】") {
            labels.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return labels
    }
}

/// Web 版の `EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/` 相当の簡易バリデーション
enum EmailValidator {
    static func isValid(_ email: String) -> Bool {
        guard !email.isEmpty,
              email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }

        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }

        let domain = parts[1]
        guard let dot = domain.firstIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) < domain.endIndex
    }
}
