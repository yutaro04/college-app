import SwiftUI

/// 匿名文通。相手はランダムに選ばれ、お互いペンネームしか分からない
struct PenPalListView: View {
    @Environment(PenPalStore.self) private var store

    @State private var writing = false

    var body: some View {
        Group {
            if store.loading {
                LoadingView()
            } else if let error = store.error, store.threads.isEmpty {
                ErrorRetryView(message: error) { Task { await store.load() } }
            } else {
                content
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $writing) {
            LetterComposeSheet(title: "誰かに手紙を出す", note: "カレッジの誰か 1 人にランダムで届きます。あなたの名前は相手に伝わりません。") { body in
                try await store.start(letter: body)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("匿名文通", systemImage: "envelope.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text("手紙はカレッジの誰かにランダムで届きます。お互いペンネームだけで、名前は明かされません。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        writing = true
                    } label: {
                        Label("手紙を書く", systemImage: "pencil.line")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .cardStyle()

                ForEach(store.threads) { thread in
                    NavigationLink {
                        PenPalThreadView(threadId: thread.id)
                    } label: {
                        ThreadRow(thread: thread)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
    }
}

private struct ThreadRow: View {
    let thread: PenPalThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: thread.unreadCount > 0 ? "envelope.badge.fill" : "envelope.open")
                .font(.system(size: 18))
                .foregroundStyle(thread.unreadCount > 0 ? Theme.primary : Theme.textTertiary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.partnerAlias)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if thread.closedAt != nil {
                        Text("終了")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    Spacer()
                    if let last = thread.lastLetter {
                        Text(DateUtil.relativePast(last.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if let last = thread.lastLetter {
                    Text((last.fromMe ? "あなた: " : "") + last.body)
                        .font(.system(size: 13))
                        .foregroundStyle(thread.unreadCount > 0 ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                }
                Text("あなたのペンネーム: \(thread.myAlias)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .cardStyle(padding: 14)
    }
}

/// 1 つの文通のやり取り
struct PenPalThreadView: View {
    let threadId: String

    @Environment(PenPalStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var letters: [PenPalLetter] = []
    @State private var replying = false
    @State private var confirmClose = false
    @State private var reporting = false

    private var thread: PenPalThread? { store.threads.first { $0.id == threadId } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(letters) { letter in
                    LetterCard(letter: letter, alias: letter.fromMe ? (thread?.myAlias ?? "") : (thread?.partnerAlias ?? ""))
                }
                if thread?.closedAt != nil {
                    Text("この文通は終了しました")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 8)
                } else if letters.last?.fromMe == true {
                    Text("返事を待っています…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 8)
                }
            }
            .padding(16)
        }
        .background(Theme.surface)
        .refreshable { await load() }
        .navigationTitle(thread?.partnerAlias ?? "文通")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if thread?.closedAt == nil {
                Button {
                    replying = true
                } label: {
                    Label("返事を書く", systemImage: "pencil.line")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("文通を終える", systemImage: "xmark.circle") { confirmClose = true }
                        .disabled(thread?.closedAt != nil)
                    Button("運営に通報する", systemImage: "exclamationmark.bubble", role: .destructive) { reporting = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("文通を終えますか？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("終える", role: .destructive) {
                Task {
                    do {
                        try await store.close(threadId: threadId)
                        toast.show("文通を終えました")
                    } catch {
                        toast.show(error.localizedDescription)
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("相手にはもう手紙が届かなくなります")
        }
        .sheet(isPresented: $replying) {
            LetterComposeSheet(title: "\(thread?.partnerAlias ?? "")さんへ", note: nil) { body in
                let sent = try await store.send(threadId: threadId, body: body)
                letters.append(sent)
            }
        }
        .sheet(isPresented: $reporting) {
            ReportSheet { reason in
                try await store.report(threadId: threadId, reason: reason)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            letters = try await store.letters(threadId: threadId)
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

private struct LetterCard: View {
    let letter: PenPalLetter
    let alias: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(letter.fromMe ? "あなた（\(alias)）より" : "\(alias) より")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(letter.fromMe ? Theme.textSecondary : Theme.primary)
                Spacer()
                Text(DateUtil.shortDateTime(letter.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(letter.body)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(letter.fromMe ? Theme.card : Color(hex: "#FFF8E7")!.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
        .padding(letter.fromMe ? .leading : .trailing, 24)
    }
}

/// 手紙を書くシート（新規・返事 共通）
private struct LetterComposeSheet: View {
    let title: String
    let note: String?
    let onSend: (String) async throws -> Void

    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15, design: .serif))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(hex: "#FFF8E7")!.opacity(0.95), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(minHeight: 220)
                Text("個人が特定できる情報（部屋番号・連絡先など）は書かないようにしましょう")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .background(Theme.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "送信中" : "送る") {
                        Task {
                            sending = true
                            defer { sending = false }
                            do {
                                try await onSend(text.trimmingCharacters(in: .whitespacesAndNewlines))
                                toast.show("手紙を送りました")
                                dismiss()
                            } catch {
                                toast.show(error.localizedDescription)
                            }
                        }
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ReportSheet: View {
    let onReport: (String) async throws -> Void

    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("どんなことがありましたか（任意）", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("運営が内容を確認します。相手にあなたが通報したことは伝わりません。")
                }
            }
            .navigationTitle("運営に通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("通報する") {
                        Task {
                            do {
                                try await onReport(reason)
                                toast.show("通報しました")
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
