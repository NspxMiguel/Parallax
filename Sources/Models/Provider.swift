import SwiftUI

/// The two assistants this app talks to. Everything provider-specific in the UI
/// derives from this enum, so adding a third one later touches one file.
enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    /// Colour is information here, not decoration: it is how a reply is
    /// attributed to its assistant when both answer the same question.
    var accent: Color {
        switch self {
        case .claude: Palette.claude
        case .gemini: Palette.gemini
        }
    }

    var keychainAccount: String {
        switch self {
        case .claude: "anthropic-api-key"
        case .gemini: "google-ai-api-key"
        }
    }

    /// Where the user goes to create a key, shown in Settings.
    var consoleURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    var defaultModelID: String {
        switch self {
        case .claude: "claude-opus-5"
        case .gemini: "gemini-2.5-pro"
        }
    }
}
