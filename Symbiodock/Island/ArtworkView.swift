import AppKit
import SwiftUI

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

/// The last artwork decoded. Views are re-evaluated on every hover and progress tick;
/// decoding a few hundred kilobytes of JPEG each time would be wasted work.
@MainActor
private enum ArtworkCache {
    private static var last: (data: Data, image: NSImage)?

    static func image(for data: Data) -> NSImage? {
        if let last, last.data == data { return last.image }
        guard let image = NSImage(data: data) else { return nil }
        last = (data, image)
        return image
    }
}
