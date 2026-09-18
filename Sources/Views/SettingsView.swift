import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    ForEach(Provider.allCases) { provider in
                        ProviderKeyRow(provider: provider)
                    }
                } header: {
                    Text(Loc.s("settings.keys"))
                } footer: {
                    Text(Loc.s("settings.keys.footer"))
                }

                Section {
                    PairingRow()
                } header: {
                    Text(Loc.s("settings.pairing"))
                } footer: {
                    Text(Loc.s("settings.pairing.footer"))
                }

                Section(Loc.s("settings.conversation")) {
                    Picker(Loc.s("mode.title"), selection: $settings.mode) {
                        ForEach(ChatMode.allCases) { mode in
                            Text(Loc.s(mode.labelKey)).tag(mode)
                        }
                    }
                    Picker(Loc.s("settings.activeProvider"), selection: $settings.activeProvider) {
                        ForEach(Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .disabled(settings.mode == .compare)
                    Toggle(Loc.s("settings.reasoning"), isOn: $settings.showReasoning)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Loc.s("settings.systemPrompt"))
                        TextField(
                            Loc.s("settings.systemPrompt.placeholder"),
                            text: $settings.systemPrompt,
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                    }
                }

                Section(Loc.s("settings.app")) {
                    Picker(Loc.s("settings.language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(Loc.s(language.labelKey)).tag(language)
                        }
                    }
                    LabeledContent(Loc.s("settings.version"), value: Self.version)
                    Text(Loc.s("settings.copyright"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Loc.s("action.settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Loc.s("action.done")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 620)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// One assistant's credentials. The key goes straight to the Keychain — it is
/// never held in the settings object and never written to a log.
private struct ProviderKeyRow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatSession.self) private var session
    let provider: Provider

    @State private var key = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProviderDot(provider: provider)
                Text(provider.displayName)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if settings.providersWithKey.contains(provider) {
                    Label(Loc.s("settings.connected"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(provider.accent)
                        .labelStyle(.titleAndIcon)
                }
            }

            // A bare SecureField in a Form reads as grey label text — give it a
            // shape so it looks like something you can type into.
            SecureField(Loc.s("settings.key.placeholder"), text: $key)
                .textContentType(.password)
                .autocorrectionDisabled()
                .font(.system(size: 16, design: .monospaced))
                .padding(.horizontal, 16)
                .frame(minHeight: Metrics.touch)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    // Only while there is nothing to overlap: a filled key runs
                    // the whole width of the field.
                    if key.isEmpty, UIPasteboard.general.hasStrings {
                        Button(Loc.s("action.paste")) {
                            key = (UIPasteboard.general.string ?? "").trimmed
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14))
                        .padding(.trailing, 12)
                    }
                }

            HStack(spacing: 12) {
                Button(Loc.s(saved ? "action.saved" : "action.save")) {
                    settings.setAPIKey(key, for: provider)
                    withAnimation(Motion.tap) { saved = true }
                    Task { await session.refreshModels(for: provider) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmed.isEmpty)

                if settings.providersWithKey.contains(provider) {
                    Button(Loc.s("action.remove"), role: .destructive) {
                        key = ""
                        settings.setAPIKey("", for: provider)
                        saved = false
                    }
                }

                Spacer()
                Link(Loc.s("settings.getKey"), destination: provider.consoleURL)
                    .font(.system(size: 14))
            }

            if let error = session.modelsError[provider] {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.danger)
            } else if let count = session.models[provider]?.count, count > 0 {
                Text(Loc.f("settings.modelsFound", count))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            key = settings.apiKey(for: provider) ?? ""
        }
        .onChange(of: key) { _, _ in saved = false }
    }
}

/// Brings the keys over from the Mac that already holds them. This exists
/// because neither assistant lets a third-party app sign in with a personal
/// account, and typing a key on a floating keyboard is its own punishment.
private struct PairingRow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatSession.self) private var session
    @State private var pairing = PairingService()

    private func bind() {
        pairing.onKeys = { provider, key in
            settings.setAPIKey(key, for: provider)
            Task { await session.refreshModels(for: provider) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch pairing.state {
            case .idle:
                Button {
                    bind()
                    pairing.start()
                } label: {
                    Label(Loc.s("pairing.start"), systemImage: "laptopcomputer.and.arrow.down")
                        .frame(minHeight: Metrics.touch)
                }
                .buttonStyle(.bordered)

            case .listening(let code, let port):
                VStack(alignment: .leading, spacing: 10) {
                    Text(code)
                        .font(.system(size: 42, weight: .semibold, design: .monospaced))
                        .tracking(6)
                    Text(Loc.s("pairing.waiting"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("scripts/send-keys.sh \(port)")
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                    Button(Loc.s("action.cancel")) { pairing.stop() }
                        .buttonStyle(.borderless)
                }

            case .received(let providers):
                Label(
                    Loc.f(
                        "pairing.received",
                        providers.map(\.displayName).joined(separator: " + ")
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(Palette.gemini)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.danger)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            #if DEBUG
                if ProcessInfo.processInfo.environment["PARALLAX_PAIRING"] == "1" {
                    bind()
                    pairing.start()
                }
            #endif
        }
        .onDisappear { pairing.stop() }
    }
}
