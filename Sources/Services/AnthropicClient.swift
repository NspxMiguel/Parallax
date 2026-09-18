import Foundation

/// Talks to the Messages API directly: there is no official Anthropic SDK for
/// Swift, so this is the documented REST shape, not a guess.
struct AnthropicClient: ChatClient {
    let provider: Provider = .claude

    /// Injected so the stream parser can be exercised without a network.
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private let base = URL(string: "https://api.anthropic.com/v1")!
    private let version = "2023-06-01"

    private func request(_ path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    func models(apiKey: String) async throws -> [ModelInfo] {
        var request = request("models?limit=100", apiKey: apiKey)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        if let failure = failure(from: response, body: data) { throw failure }

        struct Page: Decodable {
            struct Entry: Decodable {
                let id: String
                let display_name: String?
                let max_tokens: Int?
            }
            let data: [Entry]
        }
        let page = try JSONDecoder().decode(Page.self, from: data)
        return page.data.map {
            ModelInfo(
                id: $0.id,
                displayName: $0.display_name ?? $0.id,
                provider: .claude,
                maxOutputTokens: $0.max_tokens
            )
        }
    }

    func stream(_ request: ChatRequest, apiKey: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = self.request("messages", apiKey: apiKey)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: body(for: request)
                    )

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse,
                        !(200..<300).contains(http.statusCode)
                    {
                        var payload = Data()
                        for try await byte in bytes { payload.append(byte) }
                        throw ProviderError.http(
                            status: http.statusCode,
                            message: APIErrorBody.message(from: payload)
                        )
                    }

                    for try await payload in sseLines(bytes) {
                        try Task.checkCancellation()
                        guard let data = payload.data(using: .utf8),
                            let event = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        else { continue }

                        switch event["type"] as? String {
                        case "content_block_delta":
                            guard let delta = event["delta"] as? [String: Any] else { break }
                            if let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(.text(text))
                            } else if let thinking = delta["thinking"] as? String,
                                !thinking.isEmpty
                            {
                                continuation.yield(.reasoning(thinking))
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            throw ProviderError.http(status: 0, message: message ?? "")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func body(for request: ChatRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.modelID,
            "max_tokens": request.maxOutputTokens,
            "stream": true,
            "messages": request.history.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if !request.systemPrompt.isEmpty {
            body["system"] = request.systemPrompt
        }
        if request.includeReasoning {
            // Adaptive thinking is the current shape; a fixed token budget was
            // removed from these model families and is rejected with a 400.
            body["thinking"] = ["type": "adaptive", "display": "summarized"]
        }
        return body
    }
}
