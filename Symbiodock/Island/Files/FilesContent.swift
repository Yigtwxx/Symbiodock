import SwiftUI
import SymbiodockCore

/// The Files tab: the held files as tiles on the left, the selected one's actions on the
/// right, or an invitation to drop something while the shelf is empty.
struct FilesContent: View {
    let shelf: FileShelf
    let conversions: [UUID: FileConversion]
    let notice: ShelfNotice?
    /// A file drag is over the island.
    let isDropTarget: Bool
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat
    let previews: FilePreviews?
    let onSelect: (UUID) -> Void
    let onRequest: (FileRequest) -> Void

    @Environment(IslandGeometry.self) private var geometry: IslandGeometry?

    private static let tileSpacing: CGFloat = 8

    var body: some View {
        Group {
            if shelf.isEmpty {
                idle
            } else {
                HStack(spacing: 0) {
                    tiles
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)
                        .padding(.horizontal, 8)
                    if let item = shelf.selectedItems.first {
                        FileActionsColumn(
                            item: item, detail: previews?.detail(for: item),
                            conversion: conversions[item.id], notice: notice, onRequest: onRequest)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        .white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, topInset)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text(isDropTarget ? "Drop to hold" : "Drop files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tiles: some View {
        GeometryReader { proxy in
            let count = shelf.count + (isDropTarget ? 1 : 0)
            let needed = CGFloat(count) * FileTile.width + CGFloat(count - 1) * Self.tileSpacing
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.tileSpacing) {
                    if isDropTarget { placeholder }
                    ForEach(shelf.items) { item in
                        FileTile(
                            item: item, image: previews?.image(for: item),
                            isSelected: item.id == shelf.selectedItems.first?.id, onSelect: { onSelect(item.id) })
                    }
                }
            }
            .mask {
                // Fading out at the trailing edge says that the row goes on.
                if needed > proxy.size.width + 0.5 {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.88),
                            .init(color: .black.opacity(0.2), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
            // Only the visible part of the row takes a press on a tile.
            .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                geometry?.fileDragViewport = frame
            }
        }
        .frame(height: FileTile.height)
        .onDisappear { geometry?.fileDragViewport = .null }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(width: FileTile.width, height: FileTile.height)
    }
}
