import Foundation

/// What a streaming turn emits. Reasoning is kept separate from the answer so
/// the UI can fold it away instead of mixing it into the reply.
enum StreamEvent: Sendable {
    case reasoning(String)
    case text(String)
}

enum ProviderError: LocalizedError, Sendable {
    case missingKey(Provider)
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            String(
                format: String(localized: "error.missingKey"),
                provider.displayName
            )
        case .http(let status, let message):
            message.isEmpty
                ? String(format: String(localized: "error.http"), status)
                : message
        case .decoding(let detail):
            detail
        }
    }
}

/// One request, already shaped the way both providers need it.
struct ChatRequest: Sendable {
    var modelID: String
    var systemPrompt: String
    var history: [(role: ChatMessage.Role, text: String)]
    var includeReasoning: Bool
    var maxOutputTokens: Int
}

protocol ChatClient: Sendable {
    var provider: Provider { get }
    func models(apiKey: String) async throws -> [ModelInfo]
    func stream(_ request: ChatRequest, apiKey: String) -> AsyncThrowingStream<StreamEvent, Error>
}

extension ChatClient {
    /// Every provider here speaks Server-Sent Events; this pulls the `data:`
    /// payloads out of the byte stream and hands them over one by one.
    func sseLines(_ bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turns a non-200 response into an error carrying whatever the API said,
    /// because "request failed" alone never tells the user what to fix.
    func failure(from response: URLResponse, body: Data) -> ProviderError? {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return nil
        }
        let message = APIErrorBody.message(from: body)
        return .http(status: http.statusCode, message: message)
    }
}

/// Both APIs wrap errors as `{"error": {"message": "..."}}`.
enum APIErrorBody {
    static func message(from data: Data) -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return String(data: data, encoding: .utf8)?.prefix(300).description ?? ""
        }
        return message
    }
}
