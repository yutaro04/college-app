import Foundation

enum DBError: LocalizedError {
    case notSignedIn
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "ログインが必要です"
        case .http(_, let message): return message
        }
    }
}

/// Supabase の PostgREST を URLSession で直接叩く薄いラッパー。
/// Web 版の `supabase.from(...).select(...)` に相当する。
enum DB {
    private static var restBase: URL { AppConfig.supabaseURL.appendingPathComponent("rest/v1") }

    // MARK: - フィルタ生成ヘルパー（Web 版の .eq() / .gt() などに対応）

    static func select(_ columns: String) -> URLQueryItem { URLQueryItem(name: "select", value: columns) }
    static func eq(_ column: String, _ value: String) -> URLQueryItem { URLQueryItem(name: column, value: "eq.\(value)") }
    static func gt(_ column: String, _ value: String) -> URLQueryItem { URLQueryItem(name: column, value: "gt.\(value)") }
    static func notIsNull(_ column: String) -> URLQueryItem { URLQueryItem(name: column, value: "not.is.null") }
    static func order(_ column: String, ascending: Bool) -> URLQueryItem {
        URLQueryItem(name: "order", value: "\(column).\(ascending ? "asc" : "desc")")
    }
    static func limit(_ n: Int) -> URLQueryItem { URLQueryItem(name: "limit", value: String(n)) }

    // MARK: - CRUD

    static func fetch<T: Decodable>(_ table: String, _ items: [URLQueryItem], as type: T.Type) async throws -> [T] {
        let data = try await send(table: table, method: "GET", items: items, body: nil, prefer: nil)
        return try decoder.decode([T].self, from: data)
    }

    @discardableResult
    static func insert<T: Decodable>(
        _ table: String, _ body: some Encodable, returning type: T.Type
    ) async throws -> T {
        let data = try await send(
            table: table, method: "POST", items: [],
            body: try encoder.encode(body), prefer: "return=representation"
        )
        let rows = try decoder.decode([T].self, from: data)
        guard let first = rows.first else {
            throw DBError.http(status: 200, message: "作成した行を取得できませんでした")
        }
        return first
    }

    static func insert(_ table: String, _ body: some Encodable) async throws {
        _ = try await send(
            table: table, method: "POST", items: [],
            body: try encoder.encode(body), prefer: "return=minimal"
        )
    }

    static func update(_ table: String, _ body: some Encodable, _ items: [URLQueryItem]) async throws {
        _ = try await send(
            table: table, method: "PATCH", items: items,
            body: try encoder.encode(body), prefer: "return=minimal"
        )
    }

    static func delete(_ table: String, _ items: [URLQueryItem]) async throws {
        _ = try await send(table: table, method: "DELETE", items: items, body: nil, prefer: "return=minimal")
    }

    // MARK: - 実行

    private static func send(
        table: String, method: String, items: [URLQueryItem], body: Data?, prefer: String?
    ) async throws -> Data {
        guard let token = try await AuthStore.shared.accessToken() else { throw DBError.notSignedIn }

        var comps = URLComponents(url: restBase.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        if !items.isEmpty { comps.queryItems = items }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DBError.http(status: -1, message: "通信に失敗しました")
        }
        guard (200..<300).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["message"] as? String) ?? (json?["hint"] as? String) ?? "通信に失敗しました"
            throw DBError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
}
