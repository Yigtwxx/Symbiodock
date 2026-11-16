import SwiftUI
import SymbiodockCore

/// One place on the shelf: a lone file, or a drawer whose front card shows whole while the
/// cards behind it show their top edges as tabs in their own colours.
///
/// Not a button, and it takes no tap: the overlay's event monitor picks on a click without
/// travel (where on the stack comes from `StackLayout.hit`) and starts a file drag on travel;
/// a gesture here would pick twice. For the same reason the hover comes from the overlay too.
///
/// While files of the stack convert, one goo swallows the whole box, cards and tabs together
/// (`EngulfView`), and nothing rises under the pointer.
struct StackTile: View {
    let stack: ShelfStack
    let selection: Set<UUID>
    /// Where the pointer rests on this stack; nil when it is elsewhere.
    let hover: StackLayout.Hit?
    /// A dragged file would join this stack.
    let isDropTarget: Bool
    /// The stack's one cocoon while some of its files convert (`EngulfTiming.cocoon(of:)`).
    let conversion: FileConversion?
    let previews: FilePreviews?

    @Environment(IslandGeometry.self) private var geometry: IslandGeometry?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.frozenEngulf) private var frozenEngulf
    /// Names the rect this view writes, so an older copy that goes away later keeps its hands off it.
    @State private var owner = UUID()

    private static let spring = Animation.spring(response: 0.25, dampingFraction: 0.8)

    private var count: Int { stack.items.count }

    /// Where the pointer rests, unless the stack is in its cocoon: a sealed drawer does not
    /// answer the pointer.
    private var pointer: StackLayout.Hit? { conversion == nil ? hover : nil }

    /// A drawer in its cocoon takes no drop, so it never lifts or shows the outline for one.
    private var isTarget: Bool { isDropTarget && conversion == nil }

    var body: some View {
        let box = StackLayout.boxSize(count: count)
        let frames = StackLayout.cards(count: count)
        ZStack(alignment: .topLeading) {
            // Back to front, so each card covers the one behind it.
            ForEach(frames.indices.reversed(), id: \.self) { index in
                let frame = drawn(frames, index)
                card(index)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY - lift(of: index))
            }
            // Over the whole box, so it rises with the stack.
            if let conversion {
                EngulfView(size: box, conversion: conversion, frozen: frozenEngulf)
            }
        }
        .offset(y: -stackLift)
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : Self.spring, value: pointer)
        .animation(reduceMotion ? nil : Self.spring, value: isTarget)
        .background { dropOutline }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        publish(frame)
                    }
            }
        }
        .onDisappear { geometry?.withdrawFileDragRect(for: stack.id, by: owner) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isSelected(stack.items) ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func card(_ index: Int) -> some View {
        let item = stack.items[index]
        let look = emphasis(of: index)
        // With Reduce Motion nothing rises: the edge of what would have risen brightens.
        let isLit = reduceMotion && count > 1 && (pointer == .file(index) || (index == 0 && pointer == .body))
        if index == 0 {
            FileCard(
                item: item, label: labelItem, image: previews?.image(for: item), emphasis: look,
                isLit: isLit
            )
            // Pinned on the card's top edge: half on the tabs it counts, half on the card,
            // clear of the picture, which starts at that edge.
            .overlay(alignment: .topTrailing) {
                countPill.alignmentGuide(.top) { $0[VerticalAlignment.center] }
            }
            // The front card's edge falls on the tabs behind it; a soft shade keeps them apart.
            .shadow(color: .black.opacity(count > 1 ? 0.4 : 0), radius: 1.5, y: -0.5)
        } else {
            let color = FileKindPalette.tabColor(item.kind)
            CardGlass(color: color, emphasis: look, isTab: true)
                .overlay { CardEdge(color: color, emphasis: look, isTab: true, isLit: isLit) }
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: -0.5)
        }
    }

    /// While a back file's tab is hovered, the name under the picture is that file's.
    private var labelItem: ShelfItem {
        if case .file(let index) = pointer, stack.items.indices.contains(index) {
            return stack.items[index]
        }
        return stack.front
    }

    /// A drawer picked whole rings its front card and brightens every tab; a file picked on
    /// its own rings only its card, or its tab when it lies behind.
    private func emphasis(of index: Int) -> CardEmphasis {
        guard selection.contains(stack.items[index].id) else { return .plain }
        if count > 1, index > 0, isSelected(stack.items) { return .brightened }
        return .ringed
    }

    private func isSelected(_ items: [ShelfItem]) -> Bool {
        items.allSatisfy { selection.contains($0.id) }
    }

    /// A card behind ends a little below the front card's top, under its rounded corners:
    /// reaching the box's bottom as in `StackLayout`, it would show under a front card that
    /// rises.
    private func drawn(_ frames: [CGRect], _ index: Int) -> CGRect {
        guard index > 0 else { return frames[0] }
        var frame = frames[index]
        frame.size.height = frames[0].minY + 2 * CardGlass.radius - frame.minY
        return frame
    }

    /// The hovered card rises by `lift`. The cards behind it rise just enough that the tab
    /// right behind keeps a strip of `minPeek`: a card rising into a 7 pt tab would leave
    /// only a sliver of it.
    private func lift(of index: Int) -> CGFloat {
        guard !reduceMotion, count > 1, case .file(let hovered)? = pointer, index >= hovered else {
            return 0
        }
        if index == hovered { return StackLayout.lift }
        return max(0, StackLayout.lift - (StackLayout.peek(count: count) - StackLayout.minPeek))
    }

    /// A drawer rises a little under the pointer resting on its body, and so does any stack a
    /// dragged file would join. A lone tile does not rise under the pointer.
    private var stackLift: CGFloat {
        guard !reduceMotion else { return 0 }
        if isTarget || (count > 1 && pointer == .body) { return StackLayout.bodyLift }
        return 0
    }

    @ViewBuilder
    private var countPill: some View {
        if count > 1 {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 15, minHeight: 14)
                // Nearly opaque: it lies across a tab, the card's edge and the top of a picture,
                // and none of them should run through it.
                .background(.black.opacity(0.8), in: Capsule())
                .padding(5)
        }
    }

    /// Stays where the box is while the stack rises inside it, with room above for the rise.
    @ViewBuilder
    private var dropOutline: some View {
        if isTarget {
            RoundedRectangle(cornerRadius: CardGlass.radius + 3, style: .continuous)
                .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(EdgeInsets(top: -3 - StackLayout.bodyLift, leading: -3, bottom: -3, trailing: -3))
        }
    }

    private var accessibilityName: String {
        count == 1 ? stack.front.name : "\(stack.front.name) and \(count - 1) more"
    }

    private func publish(_ frame: CGRect) {
        guard let geometry else { return }
        if geometry.fileDragRects.isEmpty {
            // Once per appearance of the page: the overlay can now find stacks under the pointer.
            FileDragSource.log.debug("stack rects published")
        }
        geometry.publishFileDragRect(frame, for: stack.id, by: owner)
    }
}
