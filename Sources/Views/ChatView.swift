import SwiftUI

struct ChatView: View {
    @Environment(ChatSession.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            if settings.configuredProviders.isEmpty {
                WelcomeView()
            } else if let conversation = session.current, !conversation.isEmpty {
                transcript(conversation)
            } else {
                StartView()
            }
        }
        .navigationTitle(session.current?.title ?? Loc.s("chat.untitled"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker(Loc.s("mode.title"), selection: $settings.mode) {
                    ForEach(ChatMode.allCases) { mode in
                        Label(Loc.s(mode.labelKey), systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(session.targets) { provider in
                    ModelPicker(provider: provider)
                }
            }
        }
    }

    private func transcript(_ conversation: Conversation) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(conversation.exchanges) { exchange in
                    VStack(alignment: .leading, spacing: 20) {
                        PromptRow(message: exchange.prompt)
                        replies(for: exchange)
                    }
                    .id(exchange.id)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 20)
            // Room for the composer floating below the window.
            .padding(.bottom, 60)
        }
        // Keeps the newest text in view while it streams, without a timer.
        .defaultScrollAnchor(.bottom)
    }

    @ViewBuilder
    private func replies(for exchange: Exchange) -> some View {
        if exchange.replies.count > 1 {
            // Compare mode: one column per assistant, same question above both.
            // This is the layout the headset actually buys you.
            HStack(alignment: .top, spacing: Metrics.columnSpacing) {
                ForEach(exchange.replies) { reply in
                    ReplyView(message: reply)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if reply.id != exchange.replies.last?.id {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
        } else {
            ForEach(exchange.replies) { reply in
                ReplyView(message: reply)
            }
        }
    }
}

private struct ModelPicker: View {
    @Environment(ChatSession.self) private var session
    @Environment(AppSettings.self) private var settings
    let provider: Provider

    var body: some View {
        Menu {
            let list = session.models[provider] ?? []
            if list.isEmpty {
                Text(Loc.s("models.empty"))
            }
            ForEach(list) { model in
                Button {
                    settings.setModel(model.id, for: provider)
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model.id == settings.model(for: provider) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                Task { await session.refreshModels(for: provider) }
            } label: {
                Label(Loc.s("models.refresh"), systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 8) {
                ProviderDot(provider: provider, size: 8)
                Text(settings.model(for: provider))
                    .font(.system(size: 14, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .menuStyle(.button)
    }
}

/// No key yet — say what to do next, not what is missing.
struct WelcomeView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 22) {
            ParallaxMark(separated: true, size: 64)
            Text(Loc.s("welcome.title"))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
            Text(Loc.s("welcome.body"))
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button {
                showSettings = true
            } label: {
                Text(Loc.s("welcome.action"))
                    .frame(minHeight: Metrics.touch)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

/// Keys are in place, the conversation is empty: the next step is to ask.
struct StartView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 18) {
            ParallaxMark(separated: settings.mode == .compare, size: 54)
                .opacity(0.5)
            Text(Loc.s("start.title"))
                .font(.system(size: 22, weight: .semibold))
            Text(
                settings.mode == .compare
                    ? Loc.s("start.body.compare") : Loc.s("start.body.single")
            )
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
