import SwiftUI

/// The composer floats below the window as an ornament — the visionOS way of
/// keeping an action reachable without stealing room from the transcript.
struct ComposerView: View {
    @Environment(ChatSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var session = session

        HStack(spacing: 14) {
            TextField(placeholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .frame(minWidth: 420)

            Button(action: primaryAction) {
                Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: Metrics.touch, height: Metrics.touch)
            }
            .buttonStyle(.plain)
            .background(
                Circle().fill(buttonFill)
            )
            .disabled(!session.isStreaming && session.draft.trimmed.isEmpty)
            .animation(Motion.tap, value: session.draft.isEmpty)
            .accessibilityLabel(
                Loc.s(session.isStreaming ? "action.stop" : "action.send")
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: Metrics.composer)
        .glassBackgroundEffect(in: .capsule)
    }

    private var placeholder: String {
        settings.mode == .compare
            ? Loc.s("composer.placeholder.compare")
            : Loc.f("composer.placeholder.single", settings.activeProvider.displayName)
    }

    /// In compare mode the button carries both accents: it says who is about to
    /// answer before anyone answers.
    private var buttonFill: AnyShapeStyle {
        if session.isStreaming {
            return AnyShapeStyle(Palette.danger.opacity(0.85))
        }
        let targets = session.targets
        if targets.count > 1 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: targets.map(\.accent),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(targets.first?.accent ?? Palette.claude)
    }

    private func primaryAction() {
        session.isStreaming ? session.stop() : send()
    }

    private func send() {
        guard !session.draft.trimmed.isEmpty else { return }
        session.send()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
