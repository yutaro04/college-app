import Foundation

/// モックモード用に `URLSession.shared` の通信を横取りし、`MockBackend` の応答を返す URLProtocol。
///
/// バックエンド（services/api）宛ての通信をすべて引き受けるので、
/// 呼び出し側のコードはモックかどうかを意識しない。
final class MockURLProtocol: URLProtocol {
    /// 起動時に一度だけ呼ぶ（`AppConfig.useMockAPI` が true のとき）
    static func install() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    private static var mockedHosts: Set<String> {
        Set([AppConfig.collegeAPIBaseURL].compactMap(\.host))
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return mockedHosts.contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let body = Self.bodyData(of: request)

        // 通信している雰囲気を出すため少しだけ遅延させる
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let url = request.url else { return }
            let reply = MockBackend.shared.handle(method: request.httpMethod ?? "GET", url: url, body: body)
            let response = HTTPURLResponse(
                url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// URLProtocol に渡ってくる時点で httpBody は httpBodyStream に変換されていることがあるので両方見る
    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
