import Foundation

/// One turn in a conversation. A single user turn can carry two assistant
/// replies — one per provider — which is what compare mode renders side by side.
struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var text: String = ""
    /// Reasoning the model chose to expose, kept apart from the answer.
    var reasoning: String = ""
    /// Nil for user turns.
    var provider: Provider?
    var modelID: String?
    var createdAt: Date = Date()
    var isStreaming: Bool = false
    var failure: String?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reasoning.isEmpty
            && failure == nil
    }
}

/// A user turn plus every reply it produced. Grouping this way keeps compare
/// mode honest: the two answers always belong to the same question.
struct Exchange: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var prompt: ChatMessage
    var replies: [ChatMessage] = []

    func reply(from provider: Provider) -> ChatMessage? {
        replies.first { $0.provider == provider }
    }
}

struct Conversation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = ""
    var exchanges: [Exchange] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Which assistants answered here, so the sidebar can show it at a glance.
    var providers: Set<Provider> = []

    var isEmpty: Bool { exchanges.isEmpty }

    /// The first question, trimmed — good enough as a title and it never lies
    /// about what the conversation is.
    mutating func retitleIfNeeded() {
        guard title.isEmpty, let first = exchanges.first?.prompt.text else { return }
        let line = first
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        title = String(line.prefix(60))
    }
}
