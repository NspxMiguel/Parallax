import Foundation
import Observation

/// The engine: owns the conversations, fans a question out to one or both
/// assistants, and folds the streamed pieces back into the right reply.
@MainActor
@Observable
final class ChatSession {
    var conversations: [Conversation] = []
    var selectedID: UUID?
    var draft: String = ""
    var models: [Provider: [ModelInfo]] = [:]
    var modelsError: [Provider: String] = [:]

    let settings: AppSettings

    private let store = ConversationStore()
    private let clients: [Provider: any ChatClient] = [
        .claude: AnthropicClient(),
        .gemini: GeminiClient(),
    ]
    /// Keyed by exchange *and* provider, so the two replies of a compare
    /// turn never cancel each other.
    private var tasks: [String: Task<Void, Never>] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        conversations = store.load()
        selectedID = conversations.first?.id
    }

    // MARK: - Conversations

    var current: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    var isStreaming: Bool { !tasks.isEmpty }

    /// Which assistants answer the next question.
    var targets: [Provider] {
        switch settings.mode {
        case .single:
            [settings.activeProvider]
        case .compare:
            settings.configuredProviders.isEmpty
                ? Provider.allCases : settings.configuredProviders
        }
    }

    func newConversation() {
        stop()
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
    }

    func delete(_ id: UUID) {
        if id == selectedID { stop() }
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.first?.id }
        persist()
    }

    func renameCurrent(to title: String) {
        mutateCurrent { $0.title = title }
    }

    // MARK: - Sending

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }

        if current == nil { newConversation() }
        guard selectedID != nil else { return }

        draft = ""

        var exchange = Exchange(prompt: ChatMessage(role: .user, text: prompt))
        let providers = targets
        exchange.replies = providers.map {
            ChatMessage(
                role: .assistant,
                provider: $0,
                modelID: settings.model(for: $0),
                isStreaming: true
            )
        }
        mutateCurrent {
            $0.exchanges.append(exchange)
            $0.providers.formUnion(providers)
            $0.retitleIfNeeded()
        }

        for provider in providers {
            start(provider: provider, exchangeID: exchange.id)
        }
    }

    func retryLast() {
        guard !isStreaming, let conversation = current, let last = conversation.exchanges.last
        else { return }
        let providers = last.replies.map(\.provider).compactMap { $0 }
        mutateCurrent { conversation in
            guard let index = conversation.exchanges.indices.last else { return }
            conversation.exchanges[index].replies = providers.map {
                ChatMessage(
                    role: .assistant,
                    provider: $0,
                    modelID: self.settings.model(for: $0),
                    isStreaming: true
                )
            }
        }
        for provider in providers {
            start(provider: provider, exchangeID: last.id)
        }
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        mutateCurrent { conversation in
            for index in conversation.exchanges.indices {
                for reply in conversation.exchanges[index].replies.indices {
                    conversation.exchanges[index].replies[reply].isStreaming = false
                }
            }
        }
        persist()
    }

    private func start(provider: Provider, exchangeID: UUID) {
        guard let client = clients[provider] else { return }
        guard let apiKey = settings.apiKey(for: provider) else {
            finish(provider: provider, exchangeID: exchangeID, error: ProviderError.missingKey(provider))
            return
        }

        let modelID = settings.model(for: provider)
        let ceiling = models[provider]?.first { $0.id == modelID }?.maxOutputTokens
        let request = ChatRequest(
            modelID: modelID,
            systemPrompt: settings.systemPrompt,
            history: history(for: provider, upTo: exchangeID),
            includeReasoning: settings.showReasoning && supportsReasoning(provider, modelID),
            maxOutputTokens: min(32_000, ceiling ?? 8_192)
        )

        let key = taskKey(provider: provider, exchangeID: exchangeID)
        tasks[key] = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in client.stream(request, apiKey: apiKey) {
                    switch event {
                    case .text(let chunk):
                        self.append(text: chunk, provider: provider, exchangeID: exchangeID)
                    case .reasoning(let chunk):
                        self.append(reasoning: chunk, provider: provider, exchangeID: exchangeID)
                    }
                }
                self.finish(provider: provider, exchangeID: exchangeID, error: nil)
            } catch is CancellationError {
                self.finish(provider: provider, exchangeID: exchangeID, error: nil)
            } catch {
                self.finish(provider: provider, exchangeID: exchangeID, error: error)
            }
        }
    }

    private func supportsReasoning(_ provider: Provider, _ modelID: String) -> Bool {
        switch provider {
        case .gemini:
            return true  // The client retries without it when a model refuses.
        case .claude:
            let known = models[.claude]?.first { $0.id == modelID }
            // Unknown model (list not fetched yet): trust the family prefix.
            return known?.supportsAdaptiveThinking
                ?? ModelInfo(id: modelID, displayName: modelID, provider: .claude,
                             maxOutputTokens: nil).supportsAdaptiveThinking
        }
    }

    /// Each assistant gets its own thread of the conversation: its own previous
    /// answers, never the other one's.
    private func history(for provider: Provider, upTo exchangeID: UUID)
        -> [(role: ChatMessage.Role, text: String)]
    {
        guard let conversation = current else { return [] }
        var turns: [(role: ChatMessage.Role, text: String)] = []
        for exchange in conversation.exchanges {
            turns.append((.user, exchange.prompt.text))
            if exchange.id == exchangeID { break }
            if let reply = exchange.reply(from: provider), !reply.text.isEmpty {
                turns.append((.assistant, reply.text))
            }
        }
        return turns
    }

    // MARK: - Streaming updates

    private func append(text: String, provider: Provider, exchangeID: UUID) {
        mutateReply(provider: provider, exchangeID: exchangeID) { $0.text += text }
    }

    private func append(reasoning: String, provider: Provider, exchangeID: UUID) {
        mutateReply(provider: provider, exchangeID: exchangeID) { $0.reasoning += reasoning }
    }

    private func finish(provider: Provider, exchangeID: UUID, error: Error?) {
        tasks[taskKey(provider: provider, exchangeID: exchangeID)] = nil
        mutateReply(provider: provider, exchangeID: exchangeID) { reply in
            reply.isStreaming = false
            if let error {
                reply.failure = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        persist()
    }

    private func taskKey(provider: Provider, exchangeID: UUID) -> String {
        "\(exchangeID.uuidString)-\(provider.rawValue)"
    }

    private func mutateReply(
        provider: Provider,
        exchangeID: UUID,
        _ change: (inout ChatMessage) -> Void
    ) {
        mutateCurrent { conversation in
            guard let exchangeIndex = conversation.exchanges.firstIndex(where: {
                $0.id == exchangeID
            }),
                let replyIndex = conversation.exchanges[exchangeIndex].replies.firstIndex(where: {
                    $0.provider == provider
                })
            else { return }
            change(&conversation.exchanges[exchangeIndex].replies[replyIndex])
        }
    }

    private func mutateCurrent(_ change: (inout Conversation) -> Void) {
        guard let selectedID,
            let index = conversations.firstIndex(where: { $0.id == selectedID })
        else { return }
        change(&conversations[index])
        conversations[index].updatedAt = Date()
    }

    func persist() {
        store.save(conversations.filter { !$0.isEmpty })
    }

    // MARK: - Models

    func refreshModels(for provider: Provider) async {
        guard let client = clients[provider], let apiKey = settings.apiKey(for: provider) else {
            return
        }
        do {
            let list = try await client.models(apiKey: apiKey)
            models[provider] = list.sorted { $0.id < $1.id }
            modelsError[provider] = nil
            // A stored model that the account cannot see is worse than no
            // choice at all — fall back to something the list actually has.
            if !list.contains(where: { $0.id == settings.model(for: provider) }),
                let first = list.first
            {
                settings.setModel(first.id, for: provider)
            }
        } catch {
            modelsError[provider] =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshAllModels() async {
        for provider in Provider.allCases where settings.apiKey(for: provider) != nil {
            await refreshModels(for: provider)
        }
    }
}
