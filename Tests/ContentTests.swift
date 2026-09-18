import Foundation
import Testing

@testable import ParallaxCore

@Suite struct ContentTests {
    @Test func markdownSeparatesCodeFromProse() {
        let segments = MarkdownSegment.parse(
            """
            Here is how:

            ```swift
            let x = 1
            ```

            That is all.
            """
        )
        #expect(segments.count == 3)
        if case .code(let body, let language) = segments[1] {
            #expect(body == "let x = 1")
            #expect(language == "swift")
        } else {
            Issue.record("expected the middle segment to be code")
        }
    }

    /// Mid-stream the closing fence has not arrived yet; dropping the block
    /// would make the answer flicker.
    @Test func unterminatedCodeFenceStillRenders() {
        let segments = MarkdownSegment.parse("Try:\n\n```python\nprint(1)")
        #expect(segments.count == 2)
        if case .code(let body, _) = segments[1] {
            #expect(body == "print(1)")
        } else {
            Issue.record("expected an open fence to render as code")
        }
    }

    @Test func titleComesFromTheFirstQuestion() {
        var conversation = Conversation()
        conversation.exchanges = [
            Exchange(prompt: ChatMessage(role: .user, text: "  What is parallax?\nExplain briefly "))
        ]
        conversation.retitleIfNeeded()
        #expect(conversation.title == "What is parallax? Explain briefly")

        conversation.exchanges.append(Exchange(prompt: ChatMessage(role: .user, text: "again")))
        conversation.retitleIfNeeded()
        #expect(conversation.title == "What is parallax? Explain briefly")
    }

    @Test func adaptiveThinkingIsOnlyClaimedForFamiliesThatAcceptIt() {
        func model(_ id: String, _ provider: Provider = .claude) -> ModelInfo {
            ModelInfo(id: id, displayName: id, provider: provider, maxOutputTokens: nil)
        }
        #expect(model("claude-opus-5").supportsAdaptiveThinking)
        #expect(model("claude-sonnet-5").supportsAdaptiveThinking)
        #expect(!model("claude-haiku-4-5").supportsAdaptiveThinking)
        #expect(!model("claude-3-5-sonnet-20241022").supportsAdaptiveThinking)
        #expect(!model("gemini-2.5-pro", .gemini).supportsAdaptiveThinking)
    }

    @Test func errorBodyIsReadFromBothProviderShapes() {
        let anthropic = Data(#"{"error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
        #expect(APIErrorBody.message(from: anthropic) == "Overloaded")

        let google = Data(#"{"error":{"code":400,"message":"API key not valid"}}"#.utf8)
        #expect(APIErrorBody.message(from: google) == "API key not valid")
    }

    @Test func replyLookupIsPerProvider() {
        let exchange = Exchange(
            prompt: ChatMessage(role: .user, text: "hi"),
            replies: [
                ChatMessage(role: .assistant, text: "a", provider: .claude),
                ChatMessage(role: .assistant, text: "b", provider: .gemini),
            ]
        )
        #expect(exchange.reply(from: .claude)?.text == "a")
        #expect(exchange.reply(from: .gemini)?.text == "b")
    }
}
