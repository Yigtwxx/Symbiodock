import AppKit
import SwiftUI
import SymbiodockCore

/// Album artwork, or a music glyph when there is none.
struct ArtworkView: View {
    let data: Data?
    let size: CGFloat
    /// A disc instead of a rounded square: the bubble beside the island.
    var isRound = false

    var body: some View {
        Group {
            if let data, let image = ArtworkCache.image(for: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(outline)
        // A hairline keeps dark artwork from melting into the black island.
        .overlay {
            if isRound {
                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private var outline: AnyShape {
        isRound
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// The main artwork with, when two sources play at once, the other one's artwork behind
/// it: a little smaller and dimmer, showing on the left like the next card of a deck.
struct ArtworkStack: View {
    let front: Data?
    /// Nil when only one source plays; the stack is then just the artwork.
    let behind: NowPlayingInfo?
    let size: CGFloat

    /// How far the artwork behind shows past the front one.
    private var peek: CGFloat { (size * 0.36).rounded() }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let behind {
                ArtworkView(data: behind.artworkData, size: size * 0.84)
                    .opacity(0.7)
                    .padding(.trailing, size - size * 0.84 + peek)
                    .transition(.opacity.combined(with: .offset(x: peek)))
            }
            ArtworkView(data: front, size: size)
                // A black rim separates the two where they overlap.
                .background {
                    RoundedRectangle(cornerRadius: size * 0.22 + 1.5, style: .continuous)
                        .fill(.black)
                        .padding(behind == nil ? 0 : -1.5)
                }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: behind != nil)
    }
}

/// The last artworks decoded, each with the colours it lends to the bars. Views are
/// re-evaluated on every hover and progress tick; decoding a few hundred kilobytes of JPEG
/// each time would be wasted work. Two sources can play at once, and a track change shows
/// the old and the new for a moment.
@MainActor
enum ArtworkCache {
    private struct Entry {
        let data: Data
        let image: NSImage
        let tint: ArtworkTint?
    }

    private static let capacity = 4
    private static var recent: [Entry] = []

    static func image(for data: Data) -> NSImage? {
        entry(for: data)?.image
    }

    /// The cover's colours; nil without a cover, or for one without colour.
    static func tint(for data: Data?) -> ArtworkTint? {
        data.flatMap { entry(for: $0)?.tint }
    }

    private static func entry(for data: Data) -> Entry? {
        if let hit = recent.first(where: { $0.data == data }) { return hit }
        guard let image = NSImage(data: data) else { return nil }
        let entry = Entry(data: data, image: image, tint: tint(of: image))
        recent.append(entry)
        if recent.count > capacity { recent.removeFirst() }
        return entry
    }

    /// Reads a small copy of the cover; its rows run left to right as the cover's do.
    private static func tint(of image: NSImage) -> ArtworkTint? {
        let side = ArtworkPalette.sampleSide
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let bytes = context.data else { return nil }
        let buffer = bytes.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let pixels = (0..<side * side).map { index in
            TintColor(
                red: Double(buffer[index * 4]) / 255, green: Double(buffer[index * 4 + 1]) / 255,
                blue: Double(buffer[index * 4 + 2]) / 255)
        }
        return ArtworkPalette.tint(pixels: pixels, width: side)
    }
}
