import Foundation

/// Splits an assistant reply into prose and fenced code. Pure logic on purpose:
/// it is the piece most likely to break, and it must be testable without a
/// simulator.
enum MarkdownSegment: Equatable {
    case prose(String)
    case code(String, String?)

    static func parse(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
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
        // A fence still open means the answer is mid-stream: show what arrived
        // rather than dropping it.
        if insideFence, !code.isEmpty {
            segments.append(.code(code.joined(separator: "\n"), language))
        }
        flush(&prose, into: &segments)
        return segments
    }

    private static func flush(_ lines: inout [String], into segments: inout [MarkdownSegment]) {
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.removeAll()
        guard !body.isEmpty else { return }
        segments.append(.prose(body))
    }
}
