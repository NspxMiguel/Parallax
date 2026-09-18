import SwiftUI

struct RootView: View {
    @Environment(ChatSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false
    @State private var sidebar = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var session = session

        NavigationSplitView(columnVisibility: $sidebar) {
            SidebarView(showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 380)
        } detail: {
            ChatView()
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            ComposerView()
                .padding(.top, 14)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            #if DEBUG
                session.loadDebugFixtureIfRequested()
                if ProcessInfo.processInfo.environment["PARALLAX_SCREEN"] == "settings" {
                    showSettings = true
                }
            #endif
            await session.refreshAllModels()
        }
    }
}
