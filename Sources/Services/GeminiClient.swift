import Foundation

/// Talks to the Gemini API over REST. `streamGenerateContent` with `alt=sse`
/// is the streaming shape; the key travels in a header, never in the URL.
struct GeminiClient: ChatClient {
    let provider: Provider = .gemini

    private let base = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    private func request(_ path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    func models(apiKey: String) async throws -> [ModelInfo] {
        var request = request("models", apiKey: apiKey)
        request.url?.append(queryItems: [URLQueryItem(name: "pageSize", value: "200")])
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let failure = failure(from: response, body: data) { throw failure }

        struct Page: Decodable {
            struct Entry: Decodable {
                let name: String
                let displayName: String?
                let outputTokenLimit: Int?
                let supportedGenerationMethods: [String]?
            }
            let models: [Entry]
        }
        let page = try JSONDecoder().decode(Page.self, from: data)
        return
            page.models
            .filter { $0.supportedGenerationMethods?.contains("streamGenerateContent") ?? true }
            .map {
                let id = $0.name.replacingOccurrences(of: "models/", with: "")
                return ModelInfo(
                    id: id,
                    displayName: $0.displayName ?? id,
                    provider: .gemini,
                    maxOutputTokens: $0.outputTokenLimit
                )
            }
    }

    func stream(_ request: ChatRequest, apiKey: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await send(request, apiKey: apiKey, reasoning: request.includeReasoning)
                        { continuation.yield($0) }
                    } catch ProviderError.http(let status, let message) where status == 400 {
                        // Not every model accepts a thinking config. Rather than
                        // keep a list that rots, retry once without it.
                        guard request.includeReasoning else {
                            throw ProviderError.http(status: status, message: message)
                        }
                        try await send(request, apiKey: apiKey, reasoning: false) {
                            continuation.yield($0)
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

    private func send(
        _ chat: ChatRequest,
        apiKey: String,
        reasoning: Bool,
        yield: @escaping @Sendable (StreamEvent) -> Void
    ) async throws {
        var urlRequest = request("models/\(chat.modelID):streamGenerateContent", apiKey: apiKey)
        urlRequest.url?.append(queryItems: [URLQueryItem(name: "alt", value: "sse")])
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: body(for: chat, reasoning: reasoning)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
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
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = event["candidates"] as? [[String: Any]],
                let content = candidates.first?["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]]
            else { continue }

            for part in parts {
                guard let text = part["text"] as? String, !text.isEmpty else { continue }
                if part["thought"] as? Bool == true {
                    yield(.reasoning(text))
                } else {
                    yield(.text(text))
                }
            }
        }
    }

    private func body(for chat: ChatRequest, reasoning: Bool) -> [String: Any] {
        // Gemini calls the assistant "model"; everything else maps one to one.
        let contents = chat.history.map { turn -> [String: Any] in
            [
                "role": turn.role == .assistant ? "model" : "user",
                "parts": [["text": turn.text]],
            ]
        }
        var generationConfig: [String: Any] = ["maxOutputTokens": chat.maxOutputTokens]
        if reasoning {
            generationConfig["thinkingConfig"] = ["includeThoughts": true]
        }
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": generationConfig,
        ]
        if !chat.systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": chat.systemPrompt]]]
        }
        return body
    }
}
