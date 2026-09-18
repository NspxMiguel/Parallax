import SwiftUI

/// Every colour in the app resolves here. Nothing hardcodes a hex in a view —
/// that is what makes a theme switch land on the icons as well as the text.
enum Palette {
    /// Anthropic's terracotta and Google's blue: the colour *is* the
    /// attribution when both assistants answer the same question.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let gemini = Color(red: 0.30, green: 0.55, blue: 1.00)

    /// A hairline, not a shadow. visionOS windows already float; a drop shadow
    /// under a card is the first sign of a generated screen.
    static let hairline = Color.white.opacity(0.10)
    /// The only filled surface in the app: the user's own turn.
    static let userBubble = Color.white.opacity(0.10)

    static let danger = Color(red: 1.00, green: 0.42, blue: 0.38)
}

enum Metrics {
    /// Anything tappable is at least this tall.
    static let touch: CGFloat = 44
    static let composer: CGFloat = 56
    static let bubbleRadius: CGFloat = 22
    static let gutter: CGFloat = 28
    static let columnSpacing: CGFloat = 24
}

enum Motion {
    /// One physics for the whole app.
    static let tap = Animation.easeOut(duration: 0.15)
    static let item = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let panel = Animation.spring(response: 0.42, dampingFraction: 0.86)
}
