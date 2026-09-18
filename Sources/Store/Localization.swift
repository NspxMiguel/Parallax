import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case portuguese = "pt-BR"

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .portuguese: "language.portuguese"
        }
    }
}

/// Localization that answers to the app's own setting rather than to the
/// device language alone: a Mac in English does not mean he wants the app in
/// English. `PARALLAX_LANG=pt` forces a language for a test run.
enum Loc {
    nonisolated(unsafe) private static var bundle: Bundle = .main
    nonisolated(unsafe) private(set) static var locale: Locale = .current

    static func use(_ language: AppLanguage) {
        let forced = ProcessInfo.processInfo.environment["PARALLAX_LANG"]
        let code = resolve(forced: forced, setting: language)
        guard
            let code,
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let localized = Bundle(path: path)
        else {
            bundle = .main
            locale = .current
            return
        }
        bundle = localized
        locale = Locale(identifier: code)
    }

    private static func resolve(forced: String?, setting: AppLanguage) -> String? {
        if let forced, !forced.isEmpty {
            return forced.lowercased().hasPrefix("pt") ? "pt-BR" : "en"
        }
        return setting == .system ? nil : setting.rawValue
    }

    static func s(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: s(key), arguments: arguments)
    }
}
