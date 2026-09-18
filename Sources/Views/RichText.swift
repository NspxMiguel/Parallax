import SwiftUI

/// Both assistants answer in Markdown. Rendering it as raw text would show the
/// asterisks and the fences; this keeps prose readable and code in mono without
/// pulling in a Markdown library.
struct RichText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownSegment.parse(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let body):
                    Text(Self.inline(body))
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                case .code(let body, let language):
                    CodeBlock(code: body, language: language)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bold, italics and inline code, applied to a chunk that may still be
    /// mid-stream — an unterminated marker must not blank the whole reply.
    static func inline(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

}

private struct CodeBlock: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation(Motion.tap) { copied = true }
                } label: {
                    Label(
                        Loc.s(copied ? "action.copied" : "action.copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13))
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 15, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}
