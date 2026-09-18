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
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
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
            await session.refreshAllModels()
        }
    }
}
