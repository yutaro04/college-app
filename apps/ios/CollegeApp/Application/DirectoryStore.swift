import Foundation
import Observation

/// カレッジ生図鑑。居住者一覧・属性による絞り込み・マッチング・自分の図鑑プロフィールを扱う。
@MainActor
@Observable
final class DirectoryStore {
    private(set) var me: Resident?
    private(set) var categories: [AttributeCategory] = []
    private(set) var residents: [Resident] = []
    private(set) var matches: [ResidentMatch] = []
    private(set) var loading = true
    private(set) var error: String?

    /// 名前・タグのフリーワード検索
    var query = ""
    /// 絞り込み中のタグ（OR 条件）
    private(set) var selectedAttributes: [ResidentAttribute] = []

    func category(for key: String) -> AttributeCategory? {
        categories.first { $0.key == key }
    }

    // MARK: - 取得

    func load() async {
        error = nil
        do {
            async let me = CollegeAPI.me()
            async let categories = CollegeAPI.attributeCategories()
            async let matches = CollegeAPI.matches()
            self.me = try await me.resident
            self.categories = try await categories.sorted { $0.sortOrder < $1.sortOrder }
            self.matches = try await matches
            try await search()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func search() async throws {
        residents = try await CollegeAPI.residents(.init(
            q: query, attributeIds: selectedAttributes.map(\.id)
        ))
    }

    func toggleFilter(_ attribute: ResidentAttribute) async {
        if selectedAttributes.contains(attribute) {
            selectedAttributes.removeAll { $0 == attribute }
        } else {
            selectedAttributes.append(attribute)
        }
        try? await search()
    }

    func clearFilters() async {
        selectedAttributes = []
        try? await search()
    }

    func resident(id: String) async throws -> Resident {
        try await CollegeAPI.resident(id: id)
    }

    // MARK: - 自分の図鑑プロフィール

    func updateBio(_ bio: String) async throws {
        me = try await CollegeAPI.updateMe(displayName: nil, bio: bio)
        await refreshAfterMyChange()
    }

    func addMyAttribute(categoryKey: String, value: String) async throws {
        let added = try await CollegeAPI.addMyAttribute(categoryKey: categoryKey, value: value)
        if me?.attributes.contains(added) == false { me?.attributes.append(added) }
        await refreshAfterMyChange()
    }

    func removeMyAttribute(_ attribute: ResidentAttribute) async throws {
        try await CollegeAPI.removeMyAttribute(id: attribute.id)
        me?.attributes.removeAll { $0.id == attribute.id }
        await refreshAfterMyChange()
    }

    func suggestAttributes(categoryKey: String?, q: String) async -> [ResidentAttribute] {
        (try? await CollegeAPI.searchAttributes(categoryKey: categoryKey, q: q)) ?? []
    }

    /// 自分の属性が変わるとマッチングと一覧のタグ表示も変わるので取り直す
    private func refreshAfterMyChange() async {
        matches = (try? await CollegeAPI.matches()) ?? matches
        try? await search()
    }
}
