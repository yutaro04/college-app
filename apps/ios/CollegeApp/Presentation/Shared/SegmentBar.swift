import SwiftUI

/// タブ内の画面切り替え（ひま / 図鑑 / 交流タブの上部）に使うセグメント
protocol SegmentOption: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
    var label: String { get }
}

extension SegmentOption {
    var id: Self { self }
}

extension SegmentOption where Self: RawRepresentable, RawValue == String {
    /// 起動引数 `-InitialSegment likes` などで最初に開くセグメントを指定できる（スクリーンショット確認用）
    static func initial(_ fallback: Self) -> Self {
        UserDefaults.standard.string(forKey: "InitialSegment").flatMap(Self.init(rawValue:)) ?? fallback
    }
}

struct SegmentBar<Option: SegmentOption>: View {
    @Binding var selection: Option
    /// セグメントごとの未読数などのバッジ（0 なら出さない）
    var badge: (Option) -> Int = { _ in 0 }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Option.allCases) { option in
                let count = badge(option)
                Text(count > 0 ? "\(option.label) (\(count))" : option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }
}

/// 空き時間・募集の時間帯表示（「11/18(水) 19:00〜21:00」）
enum TimeRangeFormat {
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f
    }()

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H:mm"
        return f
    }()

    static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今日 " + day.string(from: date) }
        if Calendar.current.isDateInTomorrow(date) { return "明日 " + day.string(from: date) }
        return day.string(from: date)
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time.string(from: start))〜\(time.string(from: end))"
    }

    static func full(_ startISO: String, _ endISO: String) -> String {
        guard let start = ISODate.parse(startISO), let end = ISODate.parse(endISO) else { return "" }
        return "\(dayLabel(start)) \(timeRange(start, end))"
    }
}
