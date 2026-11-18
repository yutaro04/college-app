import SwiftUI

// MARK: - ひま募集

/// 「この時間空いてるから誰か〇〇しよう」の一覧
struct GatheringListView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HimaPlanStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    creating = true
                } label: {
                    Label("空いてる時間で人を集める", systemImage: "person.3.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                if store.gatherings.isEmpty, !store.loading {
                    Text("いまは募集がありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                ForEach(store.gatherings) { gathering in
                    GatheringCard(gathering: gathering, myId: auth.user?.id ?? "") { action in
                        await perform(action, on: gathering)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load(myId: auth.user?.id) }
        .task { await store.load(myId: auth.user?.id) }
        .sheet(isPresented: $creating) { CreateGatheringSheet() }
    }

    private func perform(_ action: GatheringCard.Action, on gathering: HimaGathering) async {
        do {
            switch action {
            case .join:
                try await store.setJoined(gathering, joined: true)
                toast.show("参加します！")
            case .leave:
                try await store.setJoined(gathering, joined: false)
                toast.show("参加を取り消しました")
            case .cancel:
                try await store.cancel(gathering)
                toast.show("募集を取り消しました")
            }
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

private struct GatheringCard: View {
    enum Action { case join, leave, cancel }

    let gathering: HimaGathering
    let myId: String
    let onAction: (Action) async -> Void

    @State private var working = false

    private var isHost: Bool { gathering.host.id == myId }
    private var joined: Bool { gathering.participants.contains { $0.id == myId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gathering.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Label(TimeRangeFormat.full(gathering.startsAt, gathering.endsAt), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                if let location = gathering.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let note = gathering.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(spacing: 8) {
                NavigationLink {
                    ResidentDetailView(residentId: gathering.host.id)
                } label: {
                    HStack(spacing: 6) {
                        gathering.host.avatar(size: 24)
                        Text(isHost ? "あなたが主催" : "\(gathering.host.displayName)さんが主催")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: -6) {
                    ForEach(gathering.participants.prefix(5)) { p in
                        p.avatar(size: 22)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
                    }
                }
                Text(gathering.capacity.map { "\(gathering.participants.count)/\($0)人" } ?? "\(gathering.participants.count)人")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(gathering.isFull ? .red : Theme.textSecondary)
            }

            Group {
                if isHost {
                    Button("募集を取り消す") { run(.cancel) }
                        .buttonStyle(SecondaryButtonStyle(tint: .red))
                } else if joined {
                    Button("参加をやめる") { run(.leave) }
                        .buttonStyle(SecondaryButtonStyle())
                } else if gathering.isFull {
                    Text("満員です")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    Button("参加する") { run(.join) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .disabled(working)
        }
        .cardStyle(padding: 14)
    }

    private func run(_ action: Action) {
        Task {
            working = true
            await onAction(action)
            working = false
        }
    }
}

/// 募集の作成。時間を決めると「その時間空いている人」が見える
private struct CreateGatheringSheet: View {
    @Environment(HimaPlanStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var note = ""
    @State private var start = CreateGatheringSheet.defaultStart
    @State private var end = CreateGatheringSheet.defaultStart.addingTimeInterval(2 * 3600)
    @State private var limited = false
    @State private var capacity = 4
    @State private var freePeople: [FreeSlot] = []
    @State private var submitting = false

    private static var defaultStart: Date {
        let next = Date().addingTimeInterval(3600)
        return Calendar.current.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    private var canSubmit: Bool {
        !submitting && !title.trimmingCharacters(in: .whitespaces).isEmpty && end > start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("何する？") {
                    TextField("例: 銭湯行く人〜 / ラウンジでボドゲ", text: $title)
                    TextField("場所（任意）", text: $location)
                    TextField("ひとこと（任意）", text: $note, axis: .vertical)
                }
                Section("いつ") {
                    DatePicker("開始", selection: $start, in: Date()...)
                    DatePicker("終了", selection: $end, in: start...)
                    Toggle("定員を決める", isOn: $limited)
                    if limited {
                        Stepper("定員 \(capacity)人", value: $capacity, in: 1...30)
                    }
                }
                Section {
                    if freePeople.isEmpty {
                        Text("この時間をまるごと空けている人はいません")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(freePeople) { slot in
                            if let resident = slot.resident {
                                HStack(spacing: 10) {
                                    resident.avatar(size: 28)
                                    Text(resident.displayName)
                                        .font(.system(size: 14))
                                    Spacer()
                                    if let s = slot.start, let e = slot.end {
                                        Text(TimeRangeFormat.timeRange(s, e))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("この時間空いている人 (\(freePeople.count))")
                } footer: {
                    Text("空き時間を登録している人だけが表示されます。募集はみんなに公開されます。")
                }
            }
            .navigationTitle("ひま募集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("募集する") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
            .task(id: "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)") {
                freePeople = await store.freeResidents(from: start, to: end)
            }
            .onChange(of: start) { _, new in
                if end <= new { end = new.addingTimeInterval(2 * 3600) }
            }
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            try await store.create(.init(
                title: title.trimmingCharacters(in: .whitespaces),
                location: location.isEmpty ? nil : location,
                startsAt: ISODate.string(from: start), endsAt: ISODate.string(from: end),
                capacity: limited ? capacity : nil,
                note: note.isEmpty ? nil : note
            ))
            toast.show("募集しました")
            dismiss()
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

// MARK: - 空き時間

/// 自分の空き時間の登録 + みんなの空き時間
struct FreeSlotsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HimaPlanStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("あなたの空き時間")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Button {
                            adding = true
                        } label: {
                            Label("追加", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    if store.mySlots.isEmpty {
                        Text("空き時間を登録すると、図鑑の個人ページやひま募集で「この時間空いてる人」として表示されます")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(store.mySlots) { slot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(TimeRangeFormat.full(slot.startsAt, slot.endsAt))
                                    .font(.system(size: 14, weight: .semibold))
                                if let note = slot.note {
                                    Text(note)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            Button {
                                Task {
                                    do { try await store.deleteSlot(slot) } catch { toast.show("削除に失敗しました") }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .cardStyle()

                Text("みんなの空き時間（7日間）")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)

                ForEach(groupedByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(TimeRangeFormat.dayLabel(group.day))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(group.slots) { slot in
                            if let resident = slot.resident, let s = slot.start, let e = slot.end {
                                NavigationLink {
                                    ResidentDetailView(residentId: resident.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        resident.avatar(size: 28)
                                        Text(resident.displayName)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(TimeRangeFormat.timeRange(s, e))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .cardStyle(padding: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load(myId: auth.user?.id) }
        .task { await store.load(myId: auth.user?.id) }
        .sheet(isPresented: $adding) { AddFreeSlotSheet() }
    }

    private var groupedByDay: [(day: Date, slots: [FreeSlot])] {
        let groups = Dictionary(grouping: store.everyonesSlots) { slot in
            Calendar.current.startOfDay(for: slot.start ?? .distantPast)
        }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }
}

private struct AddFreeSlotSheet: View {
    @Environment(HimaPlanStore.self) private var store
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date = {
        let next = Date().addingTimeInterval(3600)
        return Calendar.current.date(bySetting: .minute, value: 0, of: next) ?? next
    }()
    @State private var hours = 2.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("開始", selection: $start, in: Date()...)
                Stepper("長さ \(hours.formatted())時間", value: $hours, in: 0.5...12, step: 0.5)
                TextField("ひとこと（任意）例: 部屋にいます", text: $note)
            }
            .navigationTitle("空き時間を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task {
                            do {
                                try await store.addSlot(start: start, end: start.addingTimeInterval(hours * 3600), note: note)
                                toast.show("空き時間を追加しました")
                                dismiss()
                            } catch {
                                toast.show(error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 個人ページの「空き時間」。7 日分を 8:00〜24:00 の帯で表示する
struct FreeSlotWeekView: View {
    let slots: [FreeSlot]

    private let startHour = 8.0
    private let endHour = 24.0

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer().frame(width: 70)
                ForEach([8, 12, 16, 20], id: \.self) { h in
                    Text("\(h)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    if h != 20 { Spacer() }
                }
                Spacer()
            }
            ForEach(days, id: \.self) { day in
                HStack(spacing: 8) {
                    Text(TimeRangeFormat.dayLabel(day).replacingOccurrences(of: " ", with: "\n"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 62, alignment: .leading)
                        .lineLimit(2)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            ForEach(segments(on: day), id: \.0) { _, from, to in
                                Capsule()
                                    .fill(Color(hex: "#10B981")!)
                                    .frame(width: max(4, geo.size.width * (to - from)))
                                    .offset(x: geo.size.width * from)
                            }
                        }
                    }
                    .frame(height: 12)
                }
            }
            if slots.isEmpty {
                Text("空き時間は登録されていません")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(slots.prefix(4)) { slot in
                    Text("・\(TimeRangeFormat.full(slot.startsAt, slot.endsAt))\(slot.note.map { " \($0)" } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// その日の帯の中での位置（0〜1）
    private func segments(on day: Date) -> [(String, Double, Double)] {
        let dayStart = day.addingTimeInterval(startHour * 3600)
        let dayEnd = day.addingTimeInterval(endHour * 3600)
        let span = dayEnd.timeIntervalSince(dayStart)
        return slots.compactMap { slot in
            guard let s = slot.start, let e = slot.end, e > dayStart, s < dayEnd else { return nil }
            let from = max(s, dayStart).timeIntervalSince(dayStart) / span
            let to = min(e, dayEnd).timeIntervalSince(dayStart) / span
            return (slot.id, from, to)
        }
    }
}
