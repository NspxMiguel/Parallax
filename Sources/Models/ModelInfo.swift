import Foundation

/// A model as the provider's own API describes it. Nothing here is hardcoded:
/// model IDs age badly, so the list is fetched and cached.
struct ModelInfo: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var displayName: String
    var provider: Provider
    /// Output ceiling the API reports, used to clamp `max_tokens`.
    var maxOutputTokens: Int?

    /// Adaptive thinking is the current shape on the 4.6-and-later families.
    /// Older Claude models reject it, so ask before sending it.
    var supportsAdaptiveThinking: Bool {
        guard provider == .claude else { return false }
        let families = ["claude-opus-5", "claude-opus-4-6", "claude-opus-4-7",
                        "claude-opus-4-8", "claude-sonnet-5", "claude-sonnet-4-6",
                        "claude-fable-5"]
        return families.contains { id.hasPrefix($0) }
    }
}
