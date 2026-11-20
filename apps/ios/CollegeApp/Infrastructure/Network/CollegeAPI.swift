import Foundation

/// 新バックエンド（`services/api`、Cloudflare Workers + Hono）のクライアント。
/// エンドポイントは `services/api/README.md` の API 設計どおり。
///
/// モックモード（`AppConfig.useMockAPI`）では `MockURLProtocol` が返すダミーデータを受け取る。
enum CollegeAPI {
    // MARK: - 認証

    struct Me: Decodable {
        let email: String?
        let resident: Resident
    }

    /// 新 API のセッショントークン（無期限）。キーチェーンに置き、全リクエストに Bearer で付ける
    enum Session {
        private static let key = "college.sessionToken"

        static var token: String? {
            KeychainStore.load(key: key).flatMap { String(data: $0, encoding: .utf8) }
        }

        static func save(_ token: String) { KeychainStore.save(Data(token.utf8), key: key) }
        static func clear() { KeychainStore.delete(key: key) }
    }

    /// POST /auth/google — Google の access token を渡してセッションを発行してもらう。
    /// hlab.college 以外のアカウントはサーバーが 403 で拒否する
    static func signIn(googleAccessToken: String) async throws -> Me {
        struct Body: Encodable { let accessToken: String }
        struct Response: Decodable {
            let token: String
            let email: String?
            let resident: Resident
        }
        let body: Response = try await send(
            path: "/auth/google", method: "POST", json: Body(accessToken: googleAccessToken)
        )
        Session.save(body.token)
        return Me(email: body.email, resident: body.resident)
    }

    /// POST /auth/logout — サーバー側のセッションを消してから手元のトークンを捨てる
    static func signOut() async {
        if Session.token != nil {
            let _: Empty? = try? await send(path: "/auth/logout", method: "POST")
        }
        Session.clear()
    }

    /// 本文の無い応答（204）用
    struct Empty: Decodable {}

    /// GET /auth/me
    static func me() async throws -> Me {
        try await send(path: "/auth/me")
    }

    // MARK: - 図鑑

    struct ResidentQuery {
        var q: String = ""
        var attributeIds: [String] = []
        var categoryKey: String?
    }

    /// GET /residents
    static func residents(_ query: ResidentQuery = .init()) async throws -> [Resident] {
        struct Response: Decodable { let residents: [Resident] }
        var items: [URLQueryItem] = []
        let q = query.q.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        items += query.attributeIds.map { URLQueryItem(name: "attributeId", value: $0) }
        if let key = query.categoryKey { items.append(URLQueryItem(name: "categoryKey", value: key)) }
        let body: Response = try await send(path: "/residents", query: items)
        return body.residents
    }

    /// GET /residents/:id
    static func resident(id: String) async throws -> Resident {
        struct Response: Decodable { let resident: Resident }
        let body: Response = try await send(path: "/residents/\(id)")
        return body.resident
    }

    /// GET /residents/matches
    static func matches() async throws -> [ResidentMatch] {
        struct Response: Decodable { let matches: [ResidentMatch] }
        let body: Response = try await send(path: "/residents/matches")
        return body.matches
    }

    /// PATCH /residents/me
    static func updateMe(displayName: String?, bio: String?) async throws -> Resident {
        struct Body: Encodable {
            let displayName: String?
            let bio: String?
        }
        struct Response: Decodable { let resident: Resident }
        let body: Response = try await send(
            path: "/residents/me", method: "PATCH", json: Body(displayName: displayName, bio: bio)
        )
        return body.resident
    }

    // MARK: - 属性

    /// GET /attribute-categories
    static func attributeCategories() async throws -> [AttributeCategory] {
        struct Response: Decodable { let categories: [AttributeCategory] }
        let body: Response = try await send(path: "/attribute-categories")
        return body.categories
    }

    /// GET /attributes?categoryKey=&q= — 既存タグの検索（オートコンプリート）
    static func searchAttributes(categoryKey: String?, q: String) async throws -> [ResidentAttribute] {
        struct Response: Decodable { let attributes: [ResidentAttribute] }
        var items = [URLQueryItem(name: "q", value: q)]
        if let categoryKey { items.append(URLQueryItem(name: "categoryKey", value: categoryKey)) }
        let body: Response = try await send(path: "/attributes", query: items)
        return body.attributes
    }

    /// POST /residents/me/attributes — 既存タグがあれば再利用、なければ作成して紐付け
    static func addMyAttribute(categoryKey: String, value: String) async throws -> ResidentAttribute {
        struct Body: Encodable {
            let categoryKey: String
            let value: String
        }
        struct Response: Decodable { let attribute: ResidentAttribute }
        let body: Response = try await send(
            path: "/residents/me/attributes", method: "POST", json: Body(categoryKey: categoryKey, value: value)
        )
        return body.attribute
    }

    /// DELETE /residents/me/attributes/:attributeId
    static func removeMyAttribute(id: String) async throws {
        let _: Empty = try await send(path: "/residents/me/attributes/\(id)", method: "DELETE")
    }

    // MARK: - コーヒーチャット

    enum Box: String {
        case sent, received
    }

    /// GET /coffee-chat-requests?box=
    static func coffeeChatRequests(box: Box) async throws -> [CoffeeChatRequest] {
        struct Response: Decodable { let requests: [CoffeeChatRequest] }
        let body: Response = try await send(
            path: "/coffee-chat-requests", query: [URLQueryItem(name: "box", value: box.rawValue)]
        )
        return body.requests
    }

    /// POST /coffee-chat-requests
    static func createCoffeeChatRequest(recipientId: String, message: String?) async throws -> CoffeeChatRequest {
        struct Body: Encodable {
            let recipientId: String
            let message: String?
        }
        struct Response: Decodable { let request: CoffeeChatRequest }
        let body: Response = try await send(
            path: "/coffee-chat-requests", method: "POST", json: Body(recipientId: recipientId, message: message)
        )
        return body.request
    }

    /// PATCH /coffee-chat-requests/:id
    static func respondCoffeeChatRequest(id: String, action: CoffeeChatRequest.Action) async throws -> CoffeeChatRequest {
        struct Body: Encodable { let action: CoffeeChatRequest.Action }
        struct Response: Decodable { let request: CoffeeChatRequest }
        let body: Response = try await send(
            path: "/coffee-chat-requests/\(id)", method: "PATCH", json: Body(action: action)
        )
        return body.request
    }

    // MARK: - 実行

    private struct ErrorBody: Decodable { let error: String }

    /// `CollegeAPI+Social.swift` などからも使うので internal にしている。
    /// `upload` は JSON 以外の本文（multipart など）を (本文, Content-Type) で送るとき用
    static func send<T: Decodable>(
        path: String, method: String = "GET", query: [URLQueryItem] = [], json: (any Encodable)? = nil,
        upload: (Data, String)? = nil
    ) async throws -> T {
        var comps = URLComponents(
            url: AppConfig.collegeAPIBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }

        var req = request(comps.url!, method: method)
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(json)
        }
        if let (body, contentType) = upload {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 120
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.message("ネットワークエラー")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        await handleUnauthorized(status, request: req)
        if data.isEmpty, (200..<300).contains(status), let empty = Empty() as? T { return empty }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw APIError.message(message ?? "通信に失敗しました (\(status))")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.message("サーバーから予期しない応答が返りました (\(status))")
        }
    }

    /// 動画などのファイルを destination に保存する（既存ファイルは置き換える）
    static func download(path: String, to destination: URL) async throws {
        let req = request(AppConfig.collegeAPIBaseURL.appendingPathComponent(path), method: "GET", timeout: 120)
        let (temp, response): (URL, URLResponse)
        do {
            (temp, response) = try await URLSession.shared.download(for: req)
        } catch {
            throw APIError.message("ネットワークエラー")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        await handleUnauthorized(status, request: req)
        guard (200..<300).contains(status) else { throw APIError.message("ダウンロードに失敗しました (\(status))") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    private static func request(_ url: URL, method: String, timeout: TimeInterval = 30) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let token = Session.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private static func handleUnauthorized(_ status: Int, request: URLRequest) async {
        if status == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
            // サーバー側でセッションが消された（ログアウト・管理者による失効）のでログイン画面へ戻す
            await AuthStore.shared.sessionRevoked()
        }
    }
}

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}
