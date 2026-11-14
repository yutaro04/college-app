import SwiftUI

/// Web 版 `AddEventModal.tsx` の移植。
struct AddEventSheet: View {
    let onCreated: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = AddEventStore()

    @State private var calendarKey = "event"
    @State private var title = ""
    @State private var isAllDay = false
    @State private var date = Date()
    @State private var startTime = Self.defaultStart
    @State private var endTime = Self.defaultEnd
    @State private var roomEmail = ""
    @State private var location = ""
    @State private var descriptionText = ""
    @State private var attendees: [String] = []
    @State private var error: String?

    /// Web 版と同じく「次の正時」を既定の開始時刻にする
    private static var defaultStart: Date {
        let cal = Calendar.current
        let now = Date()
        var parts = cal.dateComponents([.year, .month, .day, .hour], from: now)
        parts.minute = 0
        parts.second = 0
        let topOfHour = cal.date(from: parts) ?? now
        return cal.date(byAdding: .hour, value: 1, to: topOfHour) ?? topOfHour
    }

    private static var defaultEnd: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.submitting
    }

    var body: some View {
        NavigationStack {
            Form {
                if let configError = store.configError {
                    Section {
                        Text("設定を取得できませんでした（\(configError)）。カレンダーは既定の選択肢で投稿できます。")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }

                Section("投稿先カレンダー") {
                    Picker("投稿先カレンダー", selection: $calendarKey) {
                        ForEach(store.calendars) { option in
                            Text(option.name).tag(option.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Section {
                    TextField("例: ハウスミーティング", text: $title)
                        .onChange(of: title) { _, new in
                            if new.count > 100 { title = String(new.prefix(100)) }
                        }
                } header: {
                    Text("タイトル *")
                }

                Section("日時") {
                    Toggle("終日", isOn: $isAllDay)
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                    if !isAllDay {
                        DatePicker("開始", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                if !store.rooms.isEmpty {
                    Section("ROOM（任意）") {
                        Picker("ROOM", selection: $roomEmail) {
                            Text("指定なし").tag("")
                            ForEach(store.rooms) { room in
                                Text(room.label).tag(room.email)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Section("場所（任意）") {
                    TextField("ROOMを選ぶと自動入力されます", text: $location)
                }

                Section("説明（任意）") {
                    TextField("", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("招待するユーザー（任意）") {
                    InviteUserPickerView(selected: $attendees)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("イベントを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.submitting ? "追加中..." : "追加") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .task { await store.loadConfig() }
        }
    }

    // MARK: - 送信

    private func submit() async {
        error = nil
        let dateKey = DateUtil.dateKey(date)
        let startISO = isAllDay ? "" : iso(for: startTime, on: dateKey)
        let endISO = isAllDay ? "" : iso(for: endTime, on: dateKey)

        if !isAllDay, endISO <= startISO {
            error = "終了時刻は開始時刻より後にしてください"
            return
        }

        do {
            let created = try await store.createEvent(.init(
                calendarKey: calendarKey,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                roomEmail: roomEmail,
                attendees: attendees,
                isAllDay: isAllDay,
                dateKey: dateKey,
                startISO: startISO,
                endISO: endISO
            ))
            onCreated(created)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 日付ピッカーの日付と時刻ピッカーの時刻を合成して UTC ISO にする
    private func iso(for time: Date, on dateKey: String) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hhmm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return DateUtil.iso(dateKey: dateKey, time: hhmm)
    }
}
