import SwiftUI

/// The question. The only filled surface in the transcript, so the eye finds
/// where each turn starts without a separator line.
struct PromptRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text)
                .font(.system(size: 17))
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.bubbleRadius, style: .continuous)
                        .fill(Palette.userBubble)
                )
        }
    }
}

/// One assistant's answer: attribution, the reasoning it chose to show, the
/// reply itself. No card — the text is the surface.
struct ReplyView: View {
    let message: ChatMessage
    @State private var showReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !message.reasoning.isEmpty {
                reasoningSection
            }

            if let failure = message.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
            }

            if !message.text.isEmpty {
                RichText(text: message.text)
            } else if message.isStreaming && message.reasoning.isEmpty {
                ThinkingIndicator(color: message.provider?.accent ?? .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let provider = message.provider {
                ProviderDot(provider: provider)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
            }
            if let modelID = message.modelID {
                Text(modelID)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if message.isStreaming {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.panel) { showReasoning.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(Loc.s("chat.reasoning"))
                    Image(systemName: showReasoning ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if showReasoning {
                Text(message.reasoning)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Palette.hairline)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Three dots that breathe while the model has not said anything yet. It is the
/// difference between "working" and "broken".
struct ThinkingIndicator: View {
    let color: Color
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(0.9))
                    .frame(width: 7, height: 7)
                    .scaleEffect(scale(for: index))
                    .opacity(0.45 + 0.55 * scale(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityLabel(Loc.s("chat.thinking"))
    }

    private func scale(for index: Int) -> CGFloat {
        let shift = Double(index) * 0.22
        return 0.7 + 0.3 * abs(sin((phase + shift) * .pi))
    }
}
