import Foundation

/// Conversations are plain JSON in Application Support. No database engine
/// earns its weight for a file this size, and a readable file is recoverable.
struct ConversationStore: Sendable {
    private let url: URL

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Parallax")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "conversations.json")
    }

    func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Conversation].self, from: data)) ?? []
    }

    func save(_ conversations: [Conversation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
