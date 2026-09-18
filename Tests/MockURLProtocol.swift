import Foundation

/// Serves canned responses so the SSE parsers can be exercised with no network,
/// no API key, and no cost.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var body: String
    }

    /// Consumed in order, one per request, so a retry can be given a different
    /// answer from the first attempt.
    nonisolated(unsafe) private static var queue: [Response] = []
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    nonisolated(unsafe) private(set) static var bodies: [Data] = []
    private static let lock = NSLock()

    static func reset(_ responses: [Response]) {
        lock.lock()
        defer { lock.unlock() }
        queue = responses
        requests = []
        bodies = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        // URLProtocol strips the body into a stream; read it back for assertions.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.bodies.append(data)
        } else {
            Self.bodies.append(request.httpBody ?? Data())
        }
        let next = Self.queue.isEmpty ? Response(body: "") : Self.queue.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
