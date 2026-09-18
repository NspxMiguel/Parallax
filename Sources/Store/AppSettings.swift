import Foundation
import Observation

/// Everything the app remembers between launches, apart from conversations and
/// the keys (Keychain) — one place, so nothing reads a default twice.
@MainActor
@Observable
final class AppSettings {
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            Loc.use(language)
        }
    }

    var mode: ChatMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }

    var activeProvider: Provider {
        didSet { defaults.set(activeProvider.rawValue, forKey: Key.activeProvider) }
    }

    var showReasoning: Bool {
        didSet { defaults.set(showReasoning, forKey: Key.showReasoning) }
    }

    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }

    /// Which providers currently have a key. Kept in memory because a view
    /// body must not reach into the Keychain on every redraw.
    private(set) var providersWithKey: Set<Provider> = []

    private var selectedModels: [String: String] {
        didSet { defaults.set(selectedModels, forKey: Key.selectedModels) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLanguage = defaults.string(forKey: Key.language) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: storedLanguage) ?? .system
        mode = ChatMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .single
        activeProvider =
            Provider(rawValue: defaults.string(forKey: Key.activeProvider) ?? "") ?? .claude
        showReasoning = defaults.object(forKey: Key.showReasoning) as? Bool ?? true
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? ""
        selectedModels = defaults.dictionary(forKey: Key.selectedModels) as? [String: String] ?? [:]
        Loc.use(language)
        refreshKeyPresence()
    }

    func model(for provider: Provider) -> String {
        selectedModels[provider.rawValue] ?? provider.defaultModelID
    }

    func setModel(_ id: String, for provider: Provider) {
        selectedModels[provider.rawValue] = id
    }

    func apiKey(for provider: Provider) -> String? {
        let key = KeychainStore.read(account: provider.keychainAccount)
        return (key?.isEmpty ?? true) ? nil : key
    }

    func setAPIKey(_ value: String, for provider: Provider) {
        KeychainStore.save(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            account: provider.keychainAccount
        )
        refreshKeyPresence()
    }

    func refreshKeyPresence() {
        providersWithKey = Set(Provider.allCases.filter { apiKey(for: $0) != nil })
    }

    var configuredProviders: [Provider] {
        Provider.allCases.filter { providersWithKey.contains($0) }
    }

    private enum Key {
        static let language = "settings.language"
        static let mode = "settings.mode"
        static let activeProvider = "settings.activeProvider"
        static let showReasoning = "settings.showReasoning"
        static let systemPrompt = "settings.systemPrompt"
        static let selectedModels = "settings.selectedModels"
    }
}

enum ChatMode: String, CaseIterable, Identifiable, Sendable {
    /// One assistant answers.
    case single
    /// Both answer the same question, side by side — the reason this app wants
    /// a headset instead of a phone.
    case compare

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .single: "mode.single"
        case .compare: "mode.compare"
        }
    }

    var symbol: String {
        switch self {
        case .single: "bubble.left.and.text.bubble.right"
        case .compare: "rectangle.split.2x1"
        }
    }
}
