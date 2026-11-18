import SwiftUI

/// Web 版 `HimaView.tsx` + `AvailabilityView.tsx` の移植。
struct HimaScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toast

    @State private var store = AvailabilityStore()
    @State private var editing = false
    @State private var inviteTarget: AvailabilityEntry?
    @State private var mode: Mode = .initial(.now)

    enum Mode: String, SegmentOption {
        case now, gather, free

        var label: String {
            switch self {
            case .now: return "いまひま"
            case .gather: return "募集"
            case .free: return "空き時間"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    LoginView()
                } else if mode == .gather {
                    GatheringListView()
                } else if mode == .free {
                    FreeSlotsView()
                } else if store.loading {
                    LoadingView()
                } else if let error = store.error, store.entries.isEmpty {
                    ErrorRetryView(message: error) { Task { await store.fetchEntries() } }
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if auth.isSignedIn { SegmentBar(selection: $mode) }
            }
            .background(Theme.surface)
            .navigationTitle("ひま")
            .navigationBarTitleDisplayMode(.large)
        }
        .task(id: auth.session?.user.id) {
            store.onInviteReceived = { name, message in
                toast.show(message.isEmpty ? "\(name)さんが誘っています" : "\(name)さん: \(message)")
            }
            await store.start()
        }
        .onDisappear { store.stop() }
        .sheet(isPresented: $editing) {
            AvailabilityEditSheet(current: store.myEntry) { message, expiresAt in
                do {
                    try await store.post(message: message, expiresAt: expiresAt)
                    toast.show("ステータスを登録しました")
                    // ここから誘いが届きうるので、このタイミングで通知許可を求める
                    await LocalNotifier.requestAuthorization()
                    return true
                } catch {
                    toast.show("登録に失敗しました")
                    return false
                }
            }
        }
        .sheet(item: $inviteTarget) { target in
            InviteSheet(target: target) { message in
                do {
                    try await store.invite(target, message: message)
                    toast.show("誘いを送りました")
                    return true
                } catch {
                    toast.show("送信に失敗しました")
                    return false
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                myStatusCard

                if !store.invites.isEmpty {
                    invitesCard
                }

                Text("暇な人たち")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)

                if others.isEmpty {
                    Text("いまは誰もいません")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(others) { entry in
                        otherCard(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.fetchEntries() }
    }

    private var others: [AvailabilityEntry] {
        store.entries.filter { $0.user_id != auth.user?.id }
    }

    // MARK: - カード

    private var myStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("あなたのステータス")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            if let mine = store.myEntry {
                Text(mine.message.isEmpty ? "暇です" : mine.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("有効期限: \(DateUtil.shortDateTime(mine.expires_at)) (\(DateUtil.relativeFuture(mine.expires_at)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                HStack(spacing: 8) {
                    Button("編集") { editing = true }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("取り下げ") {
                        Task {
                            do {
                                try await store.clear()
                                toast.show("ステータスを取り下げました")
                            } catch {
                                toast.show("失敗しました")
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: .red))
                }
                .padding(.top, 4)
            } else {
                Button("＋ 暇を表明する") { editing = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle()
    }

    private var invitesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("あなたへの誘い (\(store.invites.count))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            ForEach(store.invites) { invite in
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Theme.primary)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invite.inviter_name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if !invite.message.isEmpty {
                            Text(invite.message)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(DateUtil.relativePast(invite.created_at))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func otherCard(_ entry: AvailabilityEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.display_name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("誘う") { inviteTarget = entry }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.primary, in: Capsule())
                    .buttonStyle(.plain)
            }

            if !entry.message.isEmpty {
                Text(entry.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("〜\(DateUtil.shortDateTime(entry.expires_at)) (\(DateUtil.relativeFuture(entry.expires_at)))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardStyle()
    }
}

// MARK: - 暇を表明 / 編集

struct AvailabilityEditSheet: View {
    let current: AvailabilityEntry?
    /// 成功したら true を返す（false のときはシートを閉じない）
    let onSubmit: (String, Date) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var expiresAt = Date().addingTimeInterval(2 * 3600)
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("一言") {
                    TextField("例: お茶しませんか？", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: message) { _, new in
                            if new.count > 200 { message = String(new.prefix(200)) }
                        }
                }
                Section("有効期限") {
                    DatePicker("有効期限", selection: $expiresAt, in: Date()...)
                        .labelsHidden()
                }
            }
            .navigationTitle("暇を表明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "登録中..." : "登録") {
                        Task {
                            submitting = true
                            let ok = await onSubmit(message, expiresAt)
                            submitting = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(submitting || expiresAt <= Date())
                }
            }
            .onAppear {
                message = current?.message ?? ""
                if let iso = current?.expires_at, let date = ISODate.parse(iso) {
                    expiresAt = date
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 誘う

struct InviteSheet: View {
    let target: AvailabilityEntry
    let onSubmit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                if !target.message.isEmpty {
                    Section {
                        Text("「\(target.message)」")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Section("一言") {
                    TextField("例: カフェ行きません？", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: message) { _, new in
                            if new.count > 200 { message = String(new.prefix(200)) }
                        }
                }
            }
            .navigationTitle("\(target.display_name)さんを誘う")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "送信中..." : "送る") {
                        Task {
                            submitting = true
                            let ok = await onSubmit(message)
                            submitting = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(submitting || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ボタンスタイル

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
