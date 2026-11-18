import SwiftUI

/// 交流タブ。コーヒーチャット / 気になる / 匿名文通
struct ConnectScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(CoffeeChatStore.self) private var coffeeChat
    @Environment(LikesStore.self) private var likes
    @Environment(PenPalStore.self) private var penPal

    @State private var mode: Mode = .initial(.coffeeChat)

    enum Mode: String, SegmentOption {
        case coffeeChat, likes, penPal

        var label: String {
            switch self {
            case .coffeeChat: return "コヒチャ"
            case .likes: return "気になる"
            case .penPal: return "文通"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    LoginView()
                } else {
                    switch mode {
                    case .coffeeChat: CoffeeChatListView()
                    case .likes: LikesView()
                    case .penPal: PenPalListView()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if auth.isSignedIn {
                    SegmentBar(selection: $mode) { option in
                        switch option {
                        case .coffeeChat: return coffeeChat.pendingReceivedCount
                        case .likes: return 0
                        case .penPal: return penPal.unreadCount
                        }
                    }
                }
            }
            .background(Theme.surface)
            .navigationTitle("交流")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

/// コーヒーチャット申請の受信箱 / 送信箱
struct CoffeeChatListView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(CoffeeChatStore.self) private var store
    @Environment(ToastCenter.self) private var toast

    @State private var box: CollegeAPI.Box = .received

    var body: some View {
        Group {
            if store.loading {
                LoadingView()
            } else if let error = store.error, store.received.isEmpty, store.sent.isEmpty {
                ErrorRetryView(message: error) { Task { await store.load() } }
            } else {
                content
            }
        }
        .task { await store.load() }
    }

    private var requests: [CoffeeChatRequest] { box == .received ? store.received : store.sent }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $box) {
                    Text(store.pendingReceivedCount > 0 ? "受け取った (\(store.pendingReceivedCount))" : "受け取った")
                        .tag(CollegeAPI.Box.received)
                    Text("送った").tag(CollegeAPI.Box.sent)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if requests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textTertiary)
                        Text(box == .received ? "まだ申請は届いていません" : "図鑑から気になる人を誘ってみましょう")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    ForEach(requests) { request in
                        RequestCard(request: request, myId: auth.user?.id ?? "") { action in
                            await respond(request, action)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
    }

    private func respond(_ request: CoffeeChatRequest, _ action: CoffeeChatRequest.Action) async {
        do {
            try await store.respond(request, action: action)
            switch action {
            case .accept: toast.show("承諾しました。日程を相談しましょう！")
            case .decline: toast.show("今回は見送りました")
            case .cancel: toast.show("申請を取り消しました")
            }
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}

private struct RequestCard: View {
    let request: CoffeeChatRequest
    let myId: String
    let onAction: (CoffeeChatRequest.Action) async -> Void

    @State private var working = false

    private var counterpart: ResidentRef { request.counterpart(myId: myId) }
    private var isReceived: Bool { request.recipientId == myId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                ResidentDetailView(residentId: counterpart.id)
            } label: {
                HStack(spacing: 12) {
                    counterpart.avatar(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(counterpart.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(DateUtil.relativePast(request.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    StatusBadge(status: request.status)
                }
            }
            .buttonStyle(.plain)

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if request.status == .pending {
                if isReceived {
                    HStack(spacing: 8) {
                        Button("見送る") { run(.decline) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("承諾する") { run(.accept) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .disabled(working)
                } else {
                    Button("申請を取り消す") { run(.cancel) }
                        .buttonStyle(SecondaryButtonStyle(tint: .red))
                        .disabled(working)
                }
            } else if request.status == .accepted {
                Label("マッチしました！日程や場所は直接やり取りして決めてください", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#10B981")!)
            }
        }
        .cardStyle(padding: 14)
    }

    private func run(_ action: CoffeeChatRequest.Action) {
        Task {
            working = true
            await onAction(action)
            working = false
        }
    }
}

private struct StatusBadge: View {
    let status: CoffeeChatRequest.Status

    private var color: Color {
        switch status {
        case .pending: return Color(hex: "#F59E0B")!
        case .accepted: return Color(hex: "#10B981")!
        case .declined, .cancelled: return Theme.textTertiary
        }
    }

    var body: some View {
        Text(status.label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
