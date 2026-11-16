import AppKit
import CoreText
import SwiftUI
import SymbiodockCore

/// The round bubble right of the collapsed island while the shelf holds files: how many, on a
/// disc in the colour of the newest file's kind. Up to two more kinds show as smaller discs
/// behind it on the right, the way a second source peeks out behind the music bubble on the
/// left. Nothing in it moves at rest.
struct FilesBubble: View {
    /// Files, not stacks.
    let count: Int
    /// Newest first, at most three: the front disc's colour, then the discs behind.
    let kinds: [FileKind]
    let diameter: CGFloat

    /// The coloured disc inside each black circle: the music bubble keeps the same black rim
    /// around its artwork (22 of 28 points).
    private static let discRatio: CGFloat = 22 / 28

    var body: some View {
        let peek = IslandLayout.bubblePeek(diameter: diameter)

        ZStack(alignment: .leading) {
            // By place, not by kind: when the newest kind changes, a disc changes colour
            // instead of one leaving and another arriving.
            ForEach(Array(kinds.indices.dropFirst().prefix(2)), id: \.self) { index in
                let size = diameter * pow(IslandLayout.bubbleBehindScale, CGFloat(index))
                circle(size) {
                    disc(kinds[index], size: size * Self.discRatio)
                        .opacity(0.7)
                }
                // Each shows `peek` further past the one in front of it.
                .padding(.leading, diameter + CGFloat(index) * peek - size)
                .zIndex(-Double(index))
                .transition(.opacity.combined(with: .offset(x: -peek)))
            }
            if let front = kinds.first {
                circle(diameter) {
                    disc(front, size: diameter * Self.discRatio)
                        .overlay { number }
                }
            }
        }
        // The discs behind hang out on the right; the bubble's own frame is the front disc.
        .frame(width: diameter, height: diameter, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: kinds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "Files, 1 item" : "Files, \(count) items")
    }

    private var number: some View {
        let isCapped = count > 99
        let text = isCapped ? "99+" : "\(count)"
        let size: CGFloat = isCapped ? 8 : 11
        return Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .offset(x: Self.inkOffset(text, size: size))
    }

    /// How far to move the text so that its ink, not its box, sits in the middle of the disc.
    /// A digit's box keeps more room on its right than on its left, and a 1's box much more
    /// (measured: 0.25 pt for most digits, 0.7 pt for a 1, 1 pt for 71), so a box centred
    /// in so small a disc reads as off to the left.
    private static func inkOffset(_ text: String, size: CGFloat) -> CGFloat {
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
        return width / 2 - ink.midX
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
