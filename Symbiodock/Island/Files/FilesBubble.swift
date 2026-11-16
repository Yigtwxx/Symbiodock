import AppKit
import CoreText
import SwiftUI
import SymbiodockCore

/// The round bubble right of the collapsed island while the shelf holds files: the newest
/// file's kind as its symbol on a disc in that kind's colour, and how many files there are on
/// a badge at its top right (none for one file). Up to two more kinds show as smaller discs
/// behind it on the right, each with its own symbol, the way a second source peeks out behind
/// the music bubble on the left. Nothing in it moves at rest.
struct FilesBubble: View {
    /// Files, not stacks.
    let count: Int
    /// Newest first, at most three: the front disc's kind, then the discs behind.
    let kinds: [FileKind]
    let diameter: CGFloat

    /// The coloured disc inside each black circle: the music bubble keeps the same black rim
    /// around its artwork (22 of 28 points).
    private static let discRatio: CGFloat = 22 / 28
    /// The symbol's size on the front disc, relative to the disc (11 pt on 22): at 12 the
    /// film and the paper reached under a `99+` badge.
    private static let symbolRatio: CGFloat = 11 / 22
    /// On a disc behind only a crescent shows: its symbol is sized to that crescent, not to
    /// the disc (6.5 pt beside a 28 pt bubble).
    private static let peekSymbolRatio: CGFloat = 6.5 / 28
    /// The count badge's text.
    private static let badgeFontSize: CGFloat = 8.5
    /// How far the badge reaches past the bubble's right edge: within the hover area's padding
    /// (`IslandLayout.hitPadding`), so a press on it is a press on the bubble.
    private static let badgeOverhang: CGFloat = 3
    /// How far the badge rises above the bubble: never to the menu bar's top edge, which lies
    /// at least 2 pt above the bubble (`IslandLayout.bubbleDiameter`).
    private static let badgeRise: CGFloat = 1

    var body: some View {
        let peek = IslandLayout.bubblePeek(diameter: diameter)

        ZStack(alignment: .leading) {
            // By place, not by kind: when the newest kind changes, a disc changes colour
            // instead of one leaving and another arriving.
            ForEach(Array(kinds.indices.dropFirst().prefix(2)), id: \.self) { index in
                let size = diameter * pow(IslandLayout.bubbleBehindScale, CGFloat(index))
                let disc = size * Self.discRatio
                circle(size) {
                    ZStack {
                        self.disc(kinds[index], size: disc).opacity(0.7)
                        // In the middle of the crescent that shows past the circle in front.
                        symbol(kinds[index], size: diameter * Self.peekSymbolRatio)
                            .offset(x: (size - peek - (size - disc) / 2) / 2)
                    }
                }
                // Each shows `peek` further past the one in front of it.
                .padding(.leading, diameter + CGFloat(index) * peek - size)
                .zIndex(-Double(index))
                .transition(.opacity.combined(with: .offset(x: -peek)))
            }
            if let front = kinds.first {
                let disc = diameter * Self.discRatio
                circle(diameter) {
                    self.disc(front, size: disc)
                        .overlay { symbol(front, size: disc * Self.symbolRatio) }
                }
                .overlay(alignment: .topTrailing) { badge }
            }
        }
        // The discs behind hang out on the right; the bubble's own frame is the front disc.
        .frame(width: diameter, height: diameter, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: kinds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "Files, 1 item" : "Files, \(count) items")
    }

    /// The count, pinned across the front circle's top right edge like a drawer's count pill.
    @ViewBuilder
    private var badge: some View {
        if count > 1 {
            let text = count > 99 ? "99+" : "\(count)"
            let size = Self.badgeFontSize
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .offset(x: Self.inkOffset(text, size: size))
                .padding(.horizontal, 3)
                .frame(minWidth: 12, minHeight: 11)
                .background(.black, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.75) }
                .offset(x: Self.badgeOverhang, y: -Self.badgeRise)
        }
    }

    /// Ink offsets already measured, by text and size: the count changes rarely, and the
    /// bubble's body is evaluated far more often than that.
    private static var inkOffsets: [String: CGFloat] = [:]

    /// How far to move the text so that its ink, not its box, sits in the middle of the badge.
    /// A digit's box keeps more room on its right than on its left, and a 1's box much more
    /// (measured at 11 pt: 0.25 pt for most digits, 0.7 pt for a 1, 1 pt for 71), so a box
    /// centred in so small a badge reads as off to the left.
    private static func inkOffset(_ text: String, size: CGFloat) -> CGFloat {
        let key = "\(size) \(text)"
        if let known = inkOffsets[key] { return known }
        let base = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor
        let rounded = base.withDesign(.rounded) ?? base
        // As `.monospacedDigit()` sets it.
        let descriptor = rounded.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                .selectorIdentifier: kMonospacedNumbersSelector,
            ]]
        ])
        guard let font = NSFont(descriptor: descriptor, size: size) else { return 0 }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let offset = width / 2 - ink.midX
        inkOffsets[key] = offset
        return offset
    }

    /// The symbol the kind's cards show, in white.
    private func symbol(_ kind: FileKind, size: CGFloat) -> some View {
        Image(systemName: FileKindPalette.symbol(kind))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
    }

    /// The kind's colour, lit from the top left.
    private func disc(_ kind: FileKind, size: CGFloat) -> some View {
        let color = FileKindPalette.color(kind)
        return Circle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.78)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
            .frame(width: size, height: size)
    }

    private func circle(_ size: CGFloat, @ViewBuilder _ inside: () -> some View) -> some View {
        inside()
            .frame(width: size, height: size)
            .background(.black, in: Circle())
    }
}
