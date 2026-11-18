import Foundation

/// Web 版 `src/lib/types.ts` の CalendarEvent をそのまま移植。
/// 値は GAS（Google カレンダー）由来の文字列なので、型もできるだけ原文に合わせている。
struct CalendarEvent: Codable, Identifiable, Hashable {
    var id: String
    var calendarName: String
    var title: String
    var description: String
    var location: String
    var startISO: String
    var endISO: String
    /// yyyy-MM-dd
    var dateKey: String
    /// HH:mm
    var startTime: String
    var endTime: String
    /// M/d
    var displayDate: String
    var isAllDay: Bool
    var color: String
    var isRecurring: Bool

    /// 同じ ID でも日付違いで複数回現れる（繰り返し予定）ため、リスト用のキーは ID + 日付で作る
    var rowKey: String { "\(id)-\(dateKey)" }

    var startDate: Date? { ISODate.parse(startISO) }
    var endDate: Date? { ISODate.parse(endISO) }

    init(
        id: String, calendarName: String, title: String, description: String, location: String,
        startISO: String, endISO: String, dateKey: String, startTime: String, endTime: String,
        displayDate: String, isAllDay: Bool, color: String, isRecurring: Bool = false
    ) {
        self.id = id
        self.calendarName = calendarName
        self.title = title
        self.description = description
        self.location = location
        self.startISO = startISO
        self.endISO = endISO
        self.dateKey = dateKey
        self.startTime = startTime
        self.endTime = endTime
        self.displayDate = displayDate
        self.isAllDay = isAllDay
        self.color = color
        self.isRecurring = isRecurring
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        calendarName = try c.decodeIfPresent(String.self, forKey: .calendarName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        startISO = try c.decodeIfPresent(String.self, forKey: .startISO) ?? ""
        endISO = try c.decodeIfPresent(String.self, forKey: .endISO) ?? ""
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        displayDate = try c.decodeIfPresent(String.self, forKey: .displayDate) ?? ""
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
    }
}
