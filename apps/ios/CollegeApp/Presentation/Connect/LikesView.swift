import SwiftUI

/// 気になる（マチアプ風）。カードを右に振ると「気になる」、左で「スキップ」。
/// お互いに「気になる」したときだけマッチとして相手が分かる。
struct LikesView: View {
    @Environment(LikesStore.self) private var store
    @Environment(CoffeeChatStore.self) private var coffeeChat
    @Environment(ToastCenter.self) private var toast

    @State private var topic: String?
    @State private var drag: CGSize = .zero
    @State private var newMatch: LikeMatch?
    @State private var composingTo: ResidentRef?
    @State private var working = false

    var body: some View {
        Group {
            if store.loading {
                LoadingView()
            } else if let error = store.error, store.candidates.isEmpty, store.matches.isEmpty {
                ErrorRetryView(message: error) { Task { await store.load() } }
            } else {
                content
            }
        }
        .task { await store.load() }
        .sheet(item: $newMatch) { match in
            MatchedSheet(match: match) {
                newMatch = nil
                // 閉じるアニメーションが終わる前に次のシートを出すと表示されないので少し待つ
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    composingTo = match.resident
                }
            }
        }
        .sheet(item: $composingTo) { recipient in
            CoffeeChatComposeSheet(recipient: recipient) { message in
                do {
                    try await coffeeChat.send(to: recipient.id, message: message)
                    toast.show("コーヒーチャットを申請しました")
                    return true
                } catch {
                    toast.show(error.localizedDescription)
                    return false
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.receivedCount > 0 {
                    Label("\(store.receivedCount)人があなたを「気になる」しています。お互いに気になるとマッチします",
                          systemImage: "heart.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .cardStyle(padding: 12)
                }

                if let candidate = store.candidates.first {
                    card(candidate)
                        .id(candidate.id)
                    actionButtons(candidate)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textTertiary)
                        Text("いまいる全員をチェックしました")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                if !store.matches.isEmpty {
                    Text("マッチした人 (\(store.matches.count))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                    ForEach(store.matches) { match in
                        matchRow(match)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
    }

    // MARK: - カード

    private func card(_ candidate: ResidentMatch) -> some View {
        let resident = candidate.resident
        let shared = Set(candidate.sharedAttributes)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ResidentAvatar(id: resident.id, name: resident.displayName, avatarUrl: resident.avatarUrl, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(resident.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let affiliation = resident.affiliation {
                        Text(affiliation)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !shared.isEmpty {
                        Text("共通点 \(shared.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.primary)
                    }
                }
            }
            if let bio = resident.bio {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("どこが気になる？（タップで選ぶ・マッチしたら相手に伝わります）")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                FlowLayout(spacing: 6) {
                    ForEach(resident.attributes) { attribute in
                        Button {
                            topic = topic == attribute.value ? nil : attribute.value
                        } label: {
                            AttributeChip(attribute: attribute, highlighted: topic == attribute.value)
                                .overlay(alignment: .topTrailing) {
                                    if shared.contains(attribute) && topic != attribute.value {
                                        Circle().fill(Theme.primary).frame(width: 6, height: 6).offset(x: 2, y: -2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle(padding: 18)
        .overlay(alignment: .topTrailing) {
            if abs(drag.width) > 40 {
                Text(drag.width > 0 ? "気になる" : "スキップ")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(drag.width > 0 ? Theme.primary : Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(drag.width > 0 ? Theme.primary : Theme.textTertiary, lineWidth: 2))
                    .rotationEffect(.degrees(-12))
                    .padding(16)
            }
        }
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width) / 25))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if value.translation.width > 120 {
                        decide(candidate, like: true)
                    } else if value.translation.width < -120 {
                        decide(candidate, like: false)
                    } else {
                        withAnimation(.spring) { drag = .zero }
                    }
                }
        )
    }

    private func actionButtons(_ candidate: ResidentMatch) -> some View {
        HStack(spacing: 40) {
            Spacer()
            circleButton("xmark", color: Theme.textTertiary) { decide(candidate, like: false) }
            circleButton("heart.fill", color: Theme.primary) { decide(candidate, like: true) }
            Spacer()
        }
        .disabled(working)
    }

    private func circleButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.cardShadow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func decide(_ candidate: ResidentMatch, like: Bool) {
        Task {
            working = true
            defer { working = false }
            withAnimation(.easeIn(duration: 0.2)) { drag = CGSize(width: like ? 500 : -500, height: 0) }
            try? await Task.sleep(for: .milliseconds(200))
            do {
                if like {
                    if let match = try await store.like(candidate, topic: topic) {
                        newMatch = match
                    }
                } else {
                    try await store.pass(candidate)
                }
            } catch {
                toast.show(error.localizedDescription)
            }
            topic = nil
            drag = .zero
        }
    }

    // MARK: - マッチ

    private func matchRow(_ match: LikeMatch) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                ResidentDetailView(residentId: match.resident.id)
            } label: {
                HStack(spacing: 12) {
                    match.resident.avatar(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.resident.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let theirs = match.theirTopic {
                            Text("あなたの「\(theirs)」が気になっています")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.primary)
                        }
                        if let mine = match.myTopic {
                            Text("あなたは「\(mine)」が気になった")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if coffeeChat.pendingRequest(with: match.resident.id) == nil {
                Button {
                    composingTo = match.resident
                } label: {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.primary, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 12)
    }
}

private struct MatchedSheet: View {
    let match: LikeMatch
    let onInvite: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("マッチしました！")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.primary)
            match.resident.avatar(size: 96)
            Text("\(match.resident.displayName)さんも、あなたのことが気になっています")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            if let theirs = match.theirTopic {
                Text("気になっているところ:「\(theirs)」")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("コーヒーチャットに誘う", action: onInvite)
                .buttonStyle(PrimaryButtonStyle())
            Button("あとで") { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
