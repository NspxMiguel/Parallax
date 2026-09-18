import SwiftUI

struct SidebarView: View {
    @Environment(ChatSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Binding var showSettings: Bool

    var body: some View {
        @Bindable var session = session

        List(selection: $session.selectedID) {
            // A list is text, not a stack of cards: the spacing separates the
            // rows, and the only ornament is which assistants answered there.
            ForEach(session.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .swipeActions {
                        Button(role: .destructive) {
                            session.delete(conversation.id)
                        } label: {
                            Label(Loc.s("action.delete"), systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Loc.s("app.name"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ParallaxMark(separated: settings.mode == .compare, size: 22)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    session.newConversation()
                } label: {
                    Label(Loc.s("action.newChat"), systemImage: "square.and.pencil")
                }
                Button {
                    showSettings = true
                } label: {
                    Label(Loc.s("action.settings"), systemImage: "gearshape")
                }
            }
        }
        .overlay {
            if session.conversations.isEmpty {
                ContentUnavailableView {
                    Label(Loc.s("sidebar.empty.title"), systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(Loc.s("sidebar.empty.body"))
                }
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title.isEmpty ? Loc.s("chat.untitled") : conversation.title)
                .font(.system(size: 17))
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(Provider.allCases.filter { conversation.providers.contains($0) }) {
                    ProviderDot(provider: $0, size: 7)
                }
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
