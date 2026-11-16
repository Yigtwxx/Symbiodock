import SwiftUI
import SymbiodockCore

/// How strongly a card stands out.
enum CardEmphasis {
    case plain
    /// A tab of a drawer picked whole: brighter, without a ring of its own.
    case brightened
    /// Picked: a ring in the kind's colour.
    case ringed
}

/// The glass every card is made of: black underneath, so the cards of a drawer hide each
/// other, then a wash of the kind's colour fading downwards. The edge comes separately
/// (`CardEdge`), so it can lie over a picture that fills the card.
struct CardGlass: View {
    static let radius: CGFloat = 12

    let color: Color
    let emphasis: CardEmphasis
    /// A card behind another, of which only the top edge shows. It is washed a little
    /// stronger: a strip of a few points must still read as its colour.
    var isTab = false

    private var wash: (top: Double, bottom: Double) {
        switch (emphasis, isTab) {
        case (.plain, false): (0.24, 0.08)
        case (_, false): (0.34, 0.14)
        case (.plain, true): (0.46, 0.16)
        case (_, true): (0.6, 0.22)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        shape.fill(.black)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [color.opacity(wash.top), color.opacity(wash.bottom)],
                        startPoint: .top, endPoint: .bottom))
            }
    }
}

/// A card's rim: a hairline in the kind's colour with light catching its top, or the ring of
/// a picked card.
struct CardEdge: View {
    let color: Color
    let emphasis: CardEmphasis
    /// See `CardGlass.isTab`: a tab's hairline is brighter too.
    var isTab = false
    /// Hovered while Reduce Motion is on: the edge brightens where the card would have risen.
    var isLit = false

    private var hairline: Double {
        switch (emphasis, isTab) {
        case (.plain, false): 0.35
        case (.plain, true): 0.5
        case (_, _): 0.75
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardGlass.radius, style: .continuous)
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.22), .white.opacity(0)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)),
                lineWidth: 0.5)
            if emphasis == .ringed {
                shape.strokeBorder(color, lineWidth: isLit ? 2 : 1.5)
            } else {
                shape.strokeBorder(color.opacity(isLit ? 0.95 : hairline), lineWidth: isLit ? 1 : 0.5)
            }
        }
    }
}

/// The front card of a stack, or a lone file: its picture above, its name and extension below.
struct FileCard: View {
    /// Below the picture: the name, the extension and their margins.
    static let labelHeight: CGFloat = 31

    /// The file whose colour and picture the card shows.
    let item: ShelfItem
    /// The file named under the picture: another file of the drawer while its tab is hovered.
    let label: ShelfItem
    let image: NSImage?
    let emphasis: CardEmphasis
    var isLit = false

    var body: some View {
        let color = FileKindPalette.color(item.kind)
        VStack(spacing: 0) {
            CardPicture(item: item, image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            caption
        }
        .background { CardGlass(color: color, emphasis: emphasis) }
        .clipShape(RoundedRectangle(cornerRadius: CardGlass.radius, style: .continuous))
        .overlay { CardEdge(color: color, emphasis: emphasis, isLit: isLit) }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.baseName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(label.badge)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(FileKindPalette.color(label.kind))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.labelHeight)
    }
}

/// The top of a card. A photo, a frame or a page fills it; a document's page lies in it like a
/// small sheet of paper; anything else shows its kind's symbol.
private struct CardPicture: View {
    let item: ShelfItem
    let image: NSImage?

    var body: some View {
        switch (item.kind, image) {
        case (.image, let image?), (.video, let image?):
            filled(image, alignment: .center)
        case (.pdf, let image?):
            // A page is read from its top.
            filled(image, alignment: .top)
        case (.document, let image?):
            paper(image)
        default:
            KindSymbol(kind: item.kind).offset(y: 2)
        }
    }

    private func filled(_ image: NSImage, alignment: Alignment) -> some View {
        Color.clear
            .overlay(alignment: alignment) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }

    private func paper(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height - 14, 0)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: proxy.size.width - 24, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1.5)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(y: 2)
        }
    }
}

/// A kind's symbol, glowing faintly in its colour, so a card without a picture is not just a
/// void.
private struct KindSymbol: View {
    let kind: FileKind

    var body: some View {
        let color = FileKindPalette.color(kind)
        Image(systemName: FileKindPalette.symbol(kind))
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(color)
            .background {
                RadialGradient(
                    colors: [color.opacity(0.22), color.opacity(0)], center: .center, startRadius: 0,
                    endRadius: 30
                )
                .frame(width: 60, height: 60)
            }
    }
}

/// A file without a picture as its card shows it, the kind's symbol on the kind's glass: what
/// it looks like while it is dragged, instead of a Finder icon the shelf never shows.
struct KindSymbolCard: View {
    let kind: FileKind

    var body: some View {
        let color = FileKindPalette.color(kind)
        KindSymbol(kind: kind)
            .frame(width: 48, height: 48)
            .background { CardGlass(color: color, emphasis: .plain) }
            .clipShape(RoundedRectangle(cornerRadius: CardGlass.radius, style: .continuous))
            .overlay { CardEdge(color: color, emphasis: .plain) }
    }

    /// Drawn when a drag begins, once for each file it carries without a picture.
    static func image(for kind: FileKind) -> NSImage? {
        let renderer = ImageRenderer(content: KindSymbolCard(kind: kind))
        renderer.scale = 2
        return renderer.nsImage
    }
}

extension ShelfItem {
    /// The name a card shows: without its extension, which the card shows apart in colour.
    var baseName: String {
        guard !url.pathExtension.isEmpty, kind != .folder else { return name }
        return url.deletingPathExtension().lastPathComponent
    }
}
