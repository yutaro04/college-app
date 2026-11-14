import SwiftUI

/// Web 版 `InviteUserPicker.tsx` の移植。
/// 登録ユーザー / メーリングリストの予測変換 + 自由入力 + 個人用グループの保存に対応する。
struct InviteUserPickerView: View {
    @Binding var selected: [String]

    @State private var store = InvitePickerStore()
    @State private var query = ""
    @State private var showGroupForm = false
    @State private var groupName = ""
    @State private var groupError: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddFreeText: Bool {
        EmailValidator.isValid(trimmedQuery) && !selected.contains(trimmedQuery)
    }

    private var suggestions: [InviteSuggestion] {
        store.suggestions(query: query, selected: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selected.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selected, id: \.self) { email in
                        chip(email)
                    }
                }
            }

            TextField("名前・メールアドレスで検索、または直接入力", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)

            if !suggestions.isEmpty || canAddFreeText {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        suggestionRow(label: suggestion.label, color: Theme.textPrimary) {
                            add(suggestion.email)
                        }
                    }
                    if canAddFreeText {
                        suggestionRow(label: "「\(trimmedQuery)」を追加", color: Theme.primary) {
                            add(trimmedQuery)
                        }
                    }
                }
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            groupSection
        }
        .task { await store.load() }
    }

    // MARK: - パーツ

    private func chip(_ email: String) -> some View {
        HStack(spacing: 4) {
            Text(email)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
            Button {
                selected.removeAll { $0 == email }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func suggestionRow(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var groupSection: some View {
        if AuthStore.shared.isSignedIn {
            FlowLayout(spacing: 6) {
                ForEach(store.groups) { group in
                    HStack(spacing: 4) {
                        Button {
                            selected = Array(NSOrderedSet(array: selected + group.emails)) as? [String] ?? selected
                        } label: {
                            Text("\(group.name)（\(group.emails.count)）")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { try? await store.deleteGroup(group.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.primary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .background(Theme.primaryLight, in: Capsule())
                }

                if !showGroupForm {
                    Button("+ 選択中をグループ保存") { showGroupForm = true }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .disabled(selected.isEmpty)
                }
            }

            if showGroupForm {
                HStack(spacing: 6) {
                    TextField("グループ名", text: $groupName)
                        .font(.system(size: 12))
                    Button("保存") { Task { await saveGroup() } }
                        .font(.system(size: 12))
                        .buttonStyle(.borderedProminent)
                        .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                    Button("取消") {
                        showGroupForm = false
                        groupName = ""
                    }
                    .font(.system(size: 12))
                }
            }

            if let groupError {
                Text(groupError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - 操作

    private func add(_ email: String) {
        guard !selected.contains(email) else { return }
        selected.append(email)
        query = ""
    }

    private func saveGroup() async {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !selected.isEmpty else { return }
        do {
            try await store.createGroup(name: name, emails: selected)
            groupName = ""
            groupError = nil
            showGroupForm = false
        } catch {
            groupError = error.localizedDescription
        }
    }
}

/// チップを折り返して並べるためのレイアウト（Web 版の flex-wrap 相当）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [(index: Int, x: CGFloat, size: CGSize)]
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append((index, x, size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
