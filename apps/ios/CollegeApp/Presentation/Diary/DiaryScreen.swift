import SwiftUI

/// 日記タブ。setlog 風に毎日 2 秒を撮る「日常」と、イベントごとにみんなで撮る「イベント」
struct DiaryScreen: View {
    @Environment(AuthStore.self) private var auth

    @State private var mode: Mode = .initial(.daily)
    @State private var showingSettings = false

    enum Mode: String, SegmentOption {
        case daily, event

        var label: String {
            switch self {
            case .daily: return "日常"
            case .event: return "イベント"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .daily: DailyDiaryView()
                case .event: EventClipListView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SegmentBar(selection: $mode) }
            .background(Theme.surface)
            .navigationTitle("日記")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsScreen() }
        }
    }
}

// MARK: - 日常

private struct DailyDiaryView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selectedDay: DaySelection?
    @State private var buildingReel = false

    struct DaySelection: Identifiable {
        let dateKey: String
        var id: String { dateKey }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                todayCard

                HStack(spacing: 10) {
                    stat("連続", "\(store.streak)日", icon: "flame.fill")
                    stat("今月", "\(monthClipCount)本", icon: "film.stack")
                    stat("合計", "\(store.clips.count)本", icon: "square.stack.3d.up.fill")
                }

                monthGrid

                Button {
                    buildingReel = true
                } label: {
                    Label("思い出ビデオを作る", systemImage: "sparkles.tv")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.clips.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .overlay {
            if store.preparingSamples {
                ProgressView("サンプル動画を準備中…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await store.load() }
        .sheet(item: $selectedDay) { DayClipSheet(dateKey: $0.dateKey) }
        .sheet(isPresented: $buildingReel) { DailyReelSheet(month: month) }
    }

    // MARK: 今日

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日の2秒")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(TimeRangeFormat.dayLabel(Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            if let url = store.clips[store.todayKey] {
                Button {
                    selectedDay = DaySelection(dateKey: store.todayKey)
                } label: {
                    HStack(spacing: 14) {
                        ClipThumbnail(url: url, revision: store.revision)
                            .frame(width: 72, height: 128)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("今日はもう撮りました", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#10B981")!)
                            Text("タップで再生・撮り直し")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("今日の一瞬を2秒だけ残しましょう。毎日つなげると1本の動画になります。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                ClipSourceButtons { url in await save(url, dateKey: store.todayKey) }
            }
        }
        .cardStyle()
    }

    private func save(_ url: URL, dateKey: String) async {
        do {
            try await store.save(source: url, dateKey: dateKey)
            toast.show("保存しました")
        } catch {
            toast.show(error.localizedDescription)
        }
    }

    private func stat(_ label: String, _ value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.primary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: カレンダー

    private var monthDays: [Date?] {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: month)!
        let leading = cal.component(.weekday, from: month) - 1
        let days = range.map { cal.date(byAdding: .day, value: $0 - 1, to: month)! }
        return Array(repeating: nil, count: leading) + days
    }

    private var monthClipCount: Int {
        let prefix = String(DateUtil.dateKey(month).prefix(7))
        return store.clips.keys.filter { $0.hasPrefix(prefix) }.count
    }

    private var monthGrid: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month)!
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
            }
            .font(.system(size: 14, weight: .semibold))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(AppConstants.dayNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.aspectRatio(9 / 16, contentMode: .fit)
                    }
                }
            }
        }
        .cardStyle(padding: 12)
    }

    private func dayCell(_ day: Date) -> some View {
        let key = DateUtil.dateKey(day)
        let isFuture = day > Date()
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            selectedDay = DaySelection(dateKey: key)
        } label: {
            ZStack(alignment: .topLeading) {
                if let url = store.clips[key] {
                    ClipThumbnail(url: url, revision: store.revision, cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(isFuture ? 0.4 : 1))
                }
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .heavy : .semibold))
                    .foregroundStyle(store.clips[key] != nil ? .white : (isToday ? Theme.primary : Theme.textTertiary))
                    .shadow(color: .black.opacity(store.clips[key] != nil ? 0.5 : 0), radius: 2)
                    .padding(4)
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isToday ? Theme.primary : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

/// ある日のクリップの再生・撮り直し・削除（無ければ追加）
private struct DayClipSheet: View {
    let dateKey: String

    @Environment(DiaryStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        DateUtil.date(fromKey: dateKey).map(TimeRangeFormat.dayLabel) ?? dateKey
    }

    var body: some View {
        if let url = store.clips[dateKey] {
            VideoPlayerSheet(url: url, title: title, extraActions: AnyView(actions))
                .id(store.revision)
        } else {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("この日のクリップはまだありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    ClipSourceButtons(cameraTitle: "いま2秒撮ってこの日に入れる") { url in await save(url) }
                    Spacer()
                }
                .padding(16)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            ClipSourceButtons(cameraTitle: "撮り直す") { url in await save(url) }
            Button("この日のクリップを削除", role: .destructive) {
                store.delete(dateKey: dateKey)
                toast.show("削除しました")
                dismiss()
            }
            .font(.system(size: 13))
        }
    }

    private func save(_ url: URL) async {
        do {
            try await store.save(source: url, dateKey: dateKey)
            toast.show("保存しました")
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

/// 日常の思い出ビデオ（期間 + 任意の音源）
private struct DailyReelSheet: View {
    let month: Date

    @Environment(DiaryStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var end = Date()
    @State private var music: URL?
    @State private var composing = false
    @State private var output: ExportedVideo?

    private var count: Int { store.clips(from: start, to: end).count }

    var body: some View {
        NavigationStack {
            Form {
                Section("期間") {
                    DatePicker("から", selection: $start, displayedComponents: .date)
                    DatePicker("まで", selection: $end, in: start..., displayedComponents: .date)
                    Text("\(count)本 · 約\(Int(Double(count) * ClipProcessing.clipSeconds))秒の動画になります")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Section("音楽（任意）") {
                    MusicPickerButton(music: $music)
                }
                Section {
                    Button {
                        Task { await compose() }
                    } label: {
                        if composing {
                            HStack { ProgressView(); Text("書き出し中…") }
                        } else {
                            Text("作る")
                        }
                    }
                    .disabled(composing || count == 0)
                }
            }
            .navigationTitle("思い出ビデオ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                let cal = Calendar.current
                start = month
                let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: month)!
                end = min(monthEnd, Date())
            }
            .sheet(item: $output) { video in
                VideoPlayerSheet(url: video.url, title: "思い出ビデオ")
            }
        }
    }

    private func compose() async {
        composing = true
        defer { composing = false }
        do {
            output = ExportedVideo(url: try await store.compose(from: start, to: end, music: music))
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

/// 書き出した動画（`.sheet(item:)` 用）
struct ExportedVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - イベント

/// クリップを撮れるイベント（今日までに始まったもの）の一覧
private struct EventClipListView: View {
    @Environment(EventsStore.self) private var events
    @Environment(EventClipsStore.self) private var clips

    /// 繰り返し予定も日付ごとに別イベントとして扱う
    private var pastEvents: [CalendarEvent] {
        let todayKey = DateUtil.dateKey(Date())
        var seen = Set<String>()
        return events.events
            .filter { $0.dateKey <= todayKey }
            .filter { seen.insert($0.rowKey).inserted }
            .sorted { $0.startISO > $1.startISO }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("イベントの2秒をみんなで撮って、1本の思い出ビデオにしましょう")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)

                if pastEvents.isEmpty, !events.loading {
                    Text("今日までのイベントはありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                ForEach(pastEvents, id: \.rowKey) { event in
                    NavigationLink {
                        EventClipsView(event: event)
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: event.color) ?? Theme.primary)
                                .frame(width: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(event.displayDate) \(event.isAllDay ? "終日" : event.startTime)  \(event.location)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Label("\(clips.count(for: event))", systemImage: "film")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .cardStyle(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .task {
            await events.ensurePast()
            await clips.loadCounts()
        }
        .refreshable {
            await events.refresh()
            await events.ensurePast()
            await clips.loadCounts()
        }
    }
}

/// 1 つのイベントのクリップ（みんなの分）と思い出ビデオ
struct EventClipsView: View {
    let event: CalendarEvent

    @Environment(AuthStore.self) private var auth
    @Environment(EventClipsStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var playing: EventClip?
    @State private var music: URL?
    @State private var composing = false
    @State private var output: ExportedVideo?

    private var clips: [EventClip] { store.clips(for: event) }
    /// 思い出ビデオに使える（ダウンロード済みの）本数
    private var readyCount: Int { clips.filter { store.localURL($0) != nil }.count }
    private var myId: String { auth.user?.id ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(event.displayDate) \(event.isAllDay ? "終日" : "\(event.startTime)〜\(event.endTime)")  \(event.location)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("あなたも2秒を投稿")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    ClipSourceButtons { url in
                        do {
                            try await store.add(source: url, to: event)
                            toast.show("投稿しました")
                        } catch {
                            toast.show(error.localizedDescription)
                        }
                    }
                }
                .cardStyle()

                Text("みんなのクリップ (\(clips.count))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(clips) { clip in
                        Button {
                            playing = clip
                        } label: {
                            thumbnail(clip)
                                .aspectRatio(9 / 16, contentMode: .fit)
                                .overlay(alignment: .bottomLeading) {
                                    Text(authorName(clip))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 2)
                                        .padding(6)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.localURL(clip) == nil)
                    }
                }

                if let error = store.error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("思い出ビデオ")
                        .font(.system(size: 13, weight: .bold))
                    MusicPickerButton(music: $music, required: true)
                    Button {
                        Task { await compose() }
                    } label: {
                        if composing {
                            HStack { ProgressView().tint(.white); Text("書き出し中…") }
                        } else {
                            Label("\(readyCount)本をつなげて作る", systemImage: "sparkles.tv")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(composing || readyCount == 0 || music == nil)
                    .opacity(readyCount == 0 || music == nil ? 0.5 : 1)
                }
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.surface)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.loading {
                ProgressView("クリップを読み込み中…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await store.load(event) }
        .refreshable { await store.load(event) }
        .sheet(item: $playing) { clip in
            if let url = store.localURL(clip) {
                VideoPlayerSheet(
                    url: url, title: authorName(clip),
                    extraActions: clip.residentId == myId ? AnyView(
                        Button("自分のクリップを削除", role: .destructive) {
                            Task { await delete(clip) }
                        }
                        .font(.system(size: 13))
                    ) : nil
                )
            }
        }
        .sheet(item: $output) { video in
            VideoPlayerSheet(url: video.url, title: "思い出ビデオ")
        }
    }

    /// ダウンロードが済むまではサムネイルの代わりにくるくるを出す
    @ViewBuilder
    private func thumbnail(_ clip: EventClip) -> some View {
        if let url = store.localURL(clip) {
            ClipThumbnail(url: url)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .overlay { ProgressView() }
        }
    }

    private func authorName(_ clip: EventClip) -> String {
        clip.residentId == myId ? "あなた" : clip.author.displayName
    }

    private func delete(_ clip: EventClip) async {
        do {
            try await store.delete(clip, from: event)
            playing = nil
            toast.show("削除しました")
        } catch {
            toast.show(error.localizedDescription)
        }
    }

    private func compose() async {
        guard let music else { return }
        composing = true
        defer { composing = false }
        do {
            output = ExportedVideo(url: try await store.compose(event, music: music))
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}
