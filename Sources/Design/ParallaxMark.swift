import SwiftUI

/// The app's own sign: two lenses of the same scene. They overlap when one
/// assistant answers and separate — a real parallax offset — when both do.
/// Depth is the whole point of the headset, so the mark is the idea itself.
struct ParallaxMark: View {
    var separated: Bool
    var size: CGFloat = 26

    private var offset: CGFloat { separated ? size * 0.26 : size * 0.09 }

    var body: some View {
        ZStack {
            lens(Palette.claude).offset(x: -offset)
            lens(Palette.gemini).offset(x: offset)
        }
        .frame(width: size * 1.7, height: size)
        .animation(Motion.panel, value: separated)
        .accessibilityHidden(true)
    }

    private func lens(_ color: Color) -> some View {
        Circle()
            .strokeBorder(color.opacity(0.9), lineWidth: max(1.5, size * 0.07))
            .background(Circle().fill(color.opacity(separated ? 0.14 : 0.22)))
            .frame(width: size, height: size)
    }
}

/// The small coloured dot that attributes a reply. Same vocabulary as the mark.
struct ProviderDot: View {
    let provider: Provider
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(provider.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
