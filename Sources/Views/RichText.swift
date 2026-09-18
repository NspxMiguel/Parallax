import SwiftUI

/// Both assistants answer in Markdown. Rendering it as raw text would show the
/// asterisks and the fences; this keeps prose readable and code in mono without
/// pulling in a Markdown library.
struct RichText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Segment.parse(text).enumerated()), id: \.offset) { _, segment in
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

    enum Segment {
        case prose(String)
        case code(String, String?)

        static func parse(_ text: String) -> [Segment] {
            var segments: [Segment] = []
            var prose: [String] = []
            var code: [String] = []
            var language: String?
            var insideFence = false

            for line in text.components(separatedBy: .newlines) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    if insideFence {
                        segments.append(.code(code.joined(separator: "\n"), language))
                        code.removeAll()
                        language = nil
                    } else {
                        flush(&prose, into: &segments)
                        let tag = line.trimmingCharacters(in: .whitespaces).dropFirst(3)
                        language = tag.isEmpty ? nil : String(tag)
                    }
                    insideFence.toggle()
                    continue
                }
                if insideFence {
                    code.append(line)
                } else {
                    prose.append(line)
                }
            }
            // A fence still open means the answer is mid-stream: show what
            // arrived rather than dropping it.
            if insideFence, !code.isEmpty {
                segments.append(.code(code.joined(separator: "\n"), language))
            }
            flush(&prose, into: &segments)
            return segments
        }

        private static func flush(_ lines: inout [String], into segments: inout [Segment]) {
            let body = lines.joined(separator: "\n").trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            lines.removeAll()
            guard !body.isEmpty else { return }
            segments.append(.prose(body))
        }
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
