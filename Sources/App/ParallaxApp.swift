import SwiftUI

@main
struct ParallaxApp: App {
    @State private var settings: AppSettings
    @State private var session: ChatSession

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _session = State(initialValue: ChatSession(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(session)
                .environment(\.locale, Loc.locale)
                // Rebuilding on a language change is what makes the switch land
                // everywhere at once instead of only on the next screen.
                .id(settings.language)
        }
        .defaultSize(width: 1180, height: 820)
    }
}
