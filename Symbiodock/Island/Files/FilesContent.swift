import SwiftUI
import SymbiodockCore

/// The Files tab: the held files as stacks on the left, what can be done with the selected
/// ones on a panel at the right, or a place to drop something while the shelf is empty.
struct FilesContent: View {
    let shelf: FileShelf
    let conversions: [UUID: FileConversion]
    let notice: ShelfNotice?
    /// A file drag is over the island.
    let isDropTarget: Bool
    /// The stack a dragged file would join; nil while it would become a tile of its own.
    let dropStack: UUID?
    /// What the pointer rests on, from the overlay.
    let hover: ShelfHover?
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat
    let previews: FilePreviews?
    /// For accessibility; a pointer click picks through the overlay.
    let onSelect: ([UUID]) -> Void
    let onRequest: (FileRequest) -> Void

    @Environment(IslandGeometry.self) private var geometry: IslandGeometry?
    /// Names the viewport this view writes (see `IslandGeometry`).
    @State private var owner = UUID()

    /// Kept free at the sides and below, and between the row and the panel.
    static let margin: CGFloat = 8
    private static let stackSpacing: CGFloat = 8
    /// Room inside the scroll view around the boxes, for a drop target's outline.
    private static let outset: CGFloat = 4
    /// Above the tallest box: room for a hovered tab to rise without being cut off.
    private static let headroom = StackLayout.lift
    /// How much of the row's trailing end fades out when there is more to scroll to.
    private static let fade: CGFloat = 48

    var body: some View {
        // Sized by the island, never by the content: a taller panel would push the header up.
        GeometryReader { proxy in
            Group {
                if shelf.isEmpty {
                    // A little lower than the panel would sit: alone, it must not crowd the tabs.
                    ShelfDropZone(isTargeted: isDropTarget).padding(.top, 4)
                } else {
                    HStack(alignment: .bottom, spacing: Self.margin) {
                        row
                        let selected = shelf.selectedItems
                        if !selected.isEmpty {
                            FileActionsColumn(
                                items: selected, stackID: wholeStack(of: selected),
                                previews: previews, conversions: conversions, notice: notice,
                                onRequest: onRequest)
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom], Self.margin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .padding(.top, topInset)
    }

    /// The selection's stack, when the selection is exactly one whole stack of two or more.
    private func wholeStack(of selected: [ShelfItem]) -> UUID? {
        guard selected.count > 1, let stack = shelf.stack(holding: selected[0].id),
            stack.items.map(\.id) == selected.map(\.id)
        else { return nil }
        return stack.id
    }

    /// The boxes stand on the panel's baseline. The scroll view reaches past them by
    /// `outset` and above them by `headroom`, so neither a rising tab nor a drop target's
    /// outline is cut off; it does not ask the page for that room.
    private var row: some View {
        let stacks = shelf.stacks
        let height = StackLayout.boxSize(count: 2).height + Self.headroom + Self.outset
        return GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Self.stackSpacing) {
                    if isDropTarget {
                        // Keeps its place while a stack is the target, so the stacks do not
                        // slide away from under the pointer.
                        DropSlot().opacity(dropStack == nil ? 1 : 0)
                    }
                    ForEach(stacks) { stack in
                        StackTile(
                            stack: stack, selection: shelf.selection,
                            hover: hover?.stack == stack.id ? hover?.hit : nil,
                            isDropTarget: dropStack == stack.id, previews: previews
                        )
                        .accessibilityAction(.default) { onSelect(stack.items.map(\.id)) }
                    }
                }
                .padding(.horizontal, Self.outset)
                .padding(.bottom, Self.outset)
                .frame(height: height, alignment: .bottom)
            }
            .mask {
                // Fading out at the trailing edge says that the row goes on; all the way, so
                // no card ends in a hard cut beside the panel.
                if needed(stacks) > proxy.size.width + 0.5 {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, 1 - Self.fade / proxy.size.width)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
            // Only the visible part of the row takes a press on a stack.
            .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                geometry?.publishFileDragViewport(frame, by: owner)
            }
        }
        .frame(height: height)
        .padding(.top, -Self.headroom)
        .padding([.leading, .bottom], -Self.outset)
        .onDisappear { geometry?.withdrawFileDragViewport(by: owner) }
    }

    /// The width the boxes take, with the slot a drag adds and the outline's room.
    private func needed(_ stacks: [ShelfStack]) -> CGFloat {
        let count = stacks.count + (isDropTarget ? 1 : 0)
        return CGFloat(count) * StackLayout.tile.width + CGFloat(count - 1) * Self.stackSpacing
            + 2 * Self.outset
    }
}

/// Where a dragged file lands when no stack is under it: the first place in the row.
private struct DropSlot: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardGlass.radius, style: .continuous)
        Image(systemName: "arrow.down")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: StackLayout.tile.width, height: StackLayout.tile.height)
            .background(.white.opacity(0.05), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
    }
}

/// The empty shelf: a place to drop files, always outlined, glowing while a drag is over it.
private struct ShelfDropZone: View {
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: IslandLayout.expandedCornerRadius - FilesContent.margin, style: .continuous)
        VStack(spacing: 3) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(isTargeted ? 0.85 : 0.4))
                .padding(.bottom, 4)
            Text(isTargeted ? "Drop to hold" : "Drop files here")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.6))
            Text("They stay while you switch spaces")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(isTargeted ? 0.05 : 0), in: shape)
        .overlay {
            shape.strokeBorder(
                .white.opacity(isTargeted ? 0.45 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
