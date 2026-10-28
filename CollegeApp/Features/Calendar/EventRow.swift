import SwiftUI

/// Web 版 `EventCard.tsx` の移植。
struct EventRow: View {
    let event: CalendarEvent
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    @State private var detailOpen = false

    private var hasDescription: Bool {
        !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                dateBadge
                content
                trailing
            }

            if hasDescription {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { detailOpen.toggle() }
                } label: {
                    DisclosureChevron(isOpen: detailOpen)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if detailOpen {
                    Text(event.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - 日付バッジ

    private var dateBadge: some View {
        VStack(spacing: 1) {
            Text(monthLabel)
                .font(.system(size: 10, weight: .semibold))
            Text(dayLabel)
                .font(.system(size: 20, weight: .bold))
            Text(weekdayLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white)
        .frame(minWidth: 52)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            Color(hex: event.color) ?? Theme.primary,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.isAllDay ? "終日" : "\(event.startTime) - \(event.endTime)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            Text(event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            if !event.location.isEmpty {
                Text(event.location)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Text("Host: \(event.calendarName)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let badge {
                Text(badge.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badge.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer(minLength: 0)
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundStyle(isFavorite ? Theme.primary : Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 表示用の値

    private var badge: (label: String, color: Color)? {
        let text = (event.description + " " + event.title).lowercased()
        if text.contains("mandatory") || text.contains("必須") {
            return ("必須", Theme.primary)
        }
        if text.contains("registration") || text.contains("登録") {
            return ("REGISTRATION OPEN", Color(red: 0.063, green: 0.725, blue: 0.506))
        }
        return nil
    }

    private var components: DateComponents? {
        guard let date = event.startDate else { return nil }
        return Calendar.current.dateComponents([.month, .day, .weekday], from: date)
    }

    private var monthLabel: String {
        guard let m = components?.month else { return "" }
        return AppConstants.monthNamesEN[m - 1]
    }

    private var dayLabel: String {
        components?.day.map(String.init) ?? "-"
    }

    private var weekdayLabel: String {
        guard let w = components?.weekday else { return "" }
        return AppConstants.dayNamesEN[w - 1]
    }
}
