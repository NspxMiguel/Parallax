import Foundation
import Testing

@testable import ParallaxCore

/// These cover the part that breaks silently: the two SSE dialects.
@Suite(.serialized) struct StreamingTests {
    private func collect(
        _ stream: AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> (text: String, reasoning: String) {
        var text = ""
        var reasoning = ""
        for try await event in stream {
            switch event {
            case .text(let chunk): text += chunk
            case .reasoning(let chunk): reasoning += chunk
            }
        }
        return (text, reasoning)
    }

    private var request: ChatRequest {
        ChatRequest(
            modelID: "test-model",
            systemPrompt: "be brief",
            history: [(.user, "hello")],
            includeReasoning: true,
            maxOutputTokens: 1024
        )
    }

    @Test func anthropicSplitsReasoningFromAnswer() async throws {
        MockURLProtocol.reset([
            .init(
                body: """
                    event: content_block_delta
                    data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"weighing it"}}

                    event: content_block_delta
                    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

                    event: content_block_delta
                    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":", world"}}

                    event: message_stop
                    data: {"type":"message_stop"}

                    """)
        ])
        let client = AnthropicClient(session: MockURLProtocol.session())
        let result = try await collect(client.stream(request, apiKey: "k"))

        #expect(result.text == "Hello, world")
        #expect(result.reasoning == "weighing it")

        let body = try #require(MockURLProtocol.bodies.first)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["stream"] as? Bool == true)
        #expect(json["system"] as? String == "be brief")
        // Adaptive thinking is the current shape; budget_tokens is a 400.
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "adaptive")
        #expect(json["max_tokens"] as? Int == 1024)
    }

    @Test func anthropicSurfacesTheAPIMessage() async throws {
        MockURLProtocol.reset([
            .init(
                status: 401,
                body: #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        ])
        let client = AnthropicClient(session: MockURLProtocol.session())

        await #expect(throws: ProviderError.self) {
            _ = try await self.collect(client.stream(self.request, apiKey: "bad"))
        }
    }

    @Test func geminiMarksThoughtPartsAsReasoning() async throws {
        MockURLProtocol.reset([
            .init(
                body: """
                    data: {"candidates":[{"content":{"parts":[{"text":"considering","thought":true}]}}]}

                    data: {"candidates":[{"content":{"parts":[{"text":"Oi"}]}}]}

                    data: {"candidates":[{"content":{"parts":[{"text":", mundo"}]}}]}

                    """)
        ])
        let client = GeminiClient(session: MockURLProtocol.session())
        let result = try await collect(client.stream(request, apiKey: "k"))

        #expect(result.text == "Oi, mundo")
        #expect(result.reasoning == "considering")

        let url = try #require(MockURLProtocol.requests.first?.url?.absoluteString)
        #expect(url.contains("streamGenerateContent"))
        #expect(url.contains("alt=sse"))
        // The key belongs in a header, never in the query string.
        #expect(!url.lowercased().contains("key="))
        let header = MockURLProtocol.requests.first?
            .value(forHTTPHeaderField: "x-goog-api-key")
        #expect(header == "k")
    }

    @Test func geminiRetriesWithoutThinkingWhenTheModelRefusesIt() async throws {
        MockURLProtocol.reset([
            .init(status: 400, body: #"{"error":{"message":"thinkingConfig is not supported"}}"#),
            .init(body: #"data: {"candidates":[{"content":{"parts":[{"text":"fine"}]}}]}"# + "\n"),
        ])
        let client = GeminiClient(session: MockURLProtocol.session())
        let result = try await collect(client.stream(request, apiKey: "k"))

        #expect(result.text == "fine")
        #expect(MockURLProtocol.bodies.count == 2)

        let second = try #require(
            try JSONSerialization.jsonObject(with: MockURLProtocol.bodies[1]) as? [String: Any]
        )
        let config = try #require(second["generationConfig"] as? [String: Any])
        #expect(config["thinkingConfig"] == nil)
        // The assistant turn is "model" in Gemini's vocabulary.
        let contents = try #require(second["contents"] as? [[String: Any]])
        #expect(contents.first?["role"] as? String == "user")
    }

    @Test func geminiListsOnlyStreamableModels() async throws {
        MockURLProtocol.reset([
            .init(
                body: """
                    {"models":[
                      {"name":"models/gemini-2.5-pro","displayName":"Gemini 2.5 Pro",
                       "outputTokenLimit":65536,
                       "supportedGenerationMethods":["generateContent","streamGenerateContent"]},
                      {"name":"models/text-embedding-004","displayName":"Embedding",
                       "supportedGenerationMethods":["embedContent"]}
                    ]}
                    """)
        ])
        let client = GeminiClient(session: MockURLProtocol.session())
        let models = try await client.models(apiKey: "k")

        #expect(models.count == 1)
        #expect(models.first?.id == "gemini-2.5-pro")
        #expect(models.first?.maxOutputTokens == 65536)
    }
}
