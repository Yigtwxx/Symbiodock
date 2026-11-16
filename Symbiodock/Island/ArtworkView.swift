import AppKit
import SwiftUI
import SymbiodockCore

/// Album artwork, or a music glyph when there is none.
struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        // A hairline keeps dark artwork from melting into the black island.
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
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

/// The last artworks decoded. Views are re-evaluated on every hover and progress tick;
/// decoding a few hundred kilobytes of JPEG each time would be wasted work. Two sources
/// can play at once, and a track change shows the old and the new for a moment.
@MainActor
private enum ArtworkCache {
    private static let capacity = 4
    private static var recent: [(data: Data, image: NSImage)] = []

    static func image(for data: Data) -> NSImage? {
        if let hit = recent.first(where: { $0.data == data }) { return hit.image }
        guard let image = NSImage(data: data) else { return nil }
        recent.append((data, image))
        if recent.count > capacity { recent.removeFirst() }
        return image
    }
}
