import Combine
import SwiftUI

/// Web 版 `Header.tsx` の移植。
/// 自前のドラッグカルーセルは iOS では ScrollView + `.scrollTargetBehavior(.viewAligned)` に置き換え、
/// 左右のピーク表示と縮小は `contentMargins` と `scrollTransition` で再現している。
struct FeaturedHeader: View {
    let events: [CalendarEvent]
    let favorites: FavoritesStore
    let refreshing: Bool
    /// ステータスバー分の余白。赤い背景をそこまで伸ばすため、背景より内側で padding する
    let topInset: CGFloat
    let onRefresh: () -> Void

    @State private var activeID: String?
    @State private var detailOpenID: String?
    @State private var now = Date()

    private let peek: CGFloat = 28
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// 【全員】【新入生】付き or お気に入りのイベントだけを ID 重複なしで拾う
    private var headerEvents: [CalendarEvent] {
        var seen = Set<String>()
        return events
            .filter { DateUtil.isMandatoryEvent($0.title) || favorites.isFavorite($0.id) }
            .filter { seen.insert($0.id).inserted }
    }

    private var current: CalendarEvent? {
        headerEvents.first { $0.id == activeID } ?? headerEvents.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let current, let alert = alertText(for: current) {
                Text(alert)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.15))
            }

            if headerEvents.isEmpty {
                Text("注目イベントはありません")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                carousel
                detail
            }

            footer
        }
        .padding(.top, topInset)
        .background(Theme.primary)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
        .onReceive(timer) { now = $0 }
        .onAppear { if activeID == nil { activeID = headerEvents.first?.id } }
    }

    // MARK: - カルーセル

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(headerEvents) { event in
                    card(for: event)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                .opacity(phase.isIdentity ? 1 : 0.5)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $activeID)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, peek, for: .scrollContent)
        .frame(height: 140)
    }

    private func card(for event: CalendarEvent) -> some View {
        let isActive = event.id == activeID
        return VStack(alignment: .leading, spacing: isActive ? 6 : 4) {
            Text(event.title)
                .font(.system(size: isActive ? 18 : 14, weight: .bold))
                .lineLimit(2)
                .foregroundStyle(.white)

            if isActive {
                Text(headline(for: event))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            } else {
                Text(timeRange(for: event))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, isActive ? 20 : 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 詳細の開閉

    @ViewBuilder
    private var detail: some View {
        if let current, !current.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let isOpen = detailOpenID == current.id
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        detailOpenID = isOpen ? nil : current.id
                    }
                } label: {
                    DisclosureChevron(isOpen: isOpen, color: .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isOpen {
                    Text(current.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - ドット + 同期

    private var footer: some View {
        ZStack {
            if headerEvents.count > 1 {
                HStack(spacing: 6) {
                    ForEach(headerEvents) { event in
                        Capsule()
                            .fill(event.id == activeID ? Color.white : Color.white.opacity(0.3))
                            .frame(width: event.id == activeID ? 16 : 6, height: 6)
                            .animation(.easeOut(duration: 0.25), value: activeID)
                    }
                }
            }
            HStack {
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(
                            refreshing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: refreshing
                        )
                }
                .disabled(refreshing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - テキスト生成

    private func alertText(for event: CalendarEvent) -> String? {
        guard let start = event.startDate else { return nil }
        let countdown = DateUtil.timeUntil(start.timeIntervalSince(now))
        let labels = DateUtil.bracketLabels(event.title)
        let tag = labels.isEmpty
            ? (favorites.isFavorite(event.id) ? "お気に入り" : "")
            : labels.joined(separator: " / ")
        return tag.isEmpty ? countdown : "\(countdown) — \(tag)"
    }

    private func timeRange(for event: CalendarEvent) -> String {
        event.isAllDay ? "終日" : "\(event.startTime) - \(event.endTime)"
    }

    private func headline(for event: CalendarEvent) -> String {
        guard let date = event.startDate else { return timeRange(for: event) }
        let cal = Calendar.current
        let month = AppConstants.monthNamesEN[cal.component(.month, from: date) - 1]
        let day = cal.component(.day, from: date)
        let weekday = AppConstants.dayNamesEN[cal.component(.weekday, from: date) - 1]
        return "\(month) \(day) (\(weekday)) \(timeRange(for: event))"
    }
}
