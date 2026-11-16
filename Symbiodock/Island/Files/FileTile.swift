import SwiftUI
import SymbiodockCore

/// One held file: its preview, its name and a badge in the colour of its kind.
///
/// Not a `Button`: a press on a tile may become a file drag, which takes the mouse-up away and
/// would leave a button pressed, or click it afterwards. The overlay's event monitor selects
/// the tile on a click without travel and starts the file drag on travel.
struct FileTile: View {
    static let width: CGFloat = 64
    static let height: CGFloat = 96

    let item: ShelfItem
    let image: NSImage?
    let isSelected: Bool
    /// For accessibility; a pointer click selects through the overlay.
    let onSelect: () -> Void

    @Environment(IslandGeometry.self) private var geometry: IslandGeometry?

    var body: some View {
        VStack(spacing: 5) {
            preview
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
            badge
        }
        .padding(.top, 6)
        .frame(width: Self.width, height: Self.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.10 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // A press here drags the file, not the island.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        publish(frame)
                    }
            }
        }
        .onDisappear { geometry?.fileDragRects[item.id] = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
    }

    private func publish(_ frame: CGRect) {
        guard let geometry else { return }
        if geometry.fileDragRects.isEmpty {
            // Once per appearance of the page: the overlay can now find tiles under a press.
            FileDragSource.log.debug("tile rects published")
        }
        geometry.fileDragRects[item.id] = frame
    }

    private var preview: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var badge: some View {
        let color = FileKindPalette.color(item.kind)
        return Text(item.badge)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}
