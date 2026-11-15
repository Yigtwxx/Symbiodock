import AppKit
import SwiftUI
import SymbiodockCore

/// A purple dashed line that runs clockwise around the collapsed island while the session
/// the agents face speaks for compacts its conversation. It lies on the island's outline,
/// inside it, and leaves out the edges against the screen, like `RimLight`. Live, the
/// dashes move by Core Animation (`MarchingRim`); still (renders, Reduce Motion) SwiftUI
/// draws them once.
struct CompactingRim: View {
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>
    /// Draws the dashes where they are this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let lineWidth: CGFloat = 1.5
    static let dash: CGFloat = 6
    static let gap: CGFloat = 5
    /// How fast the dashes run along the rim, in points a second.
    static let speed: CGFloat = 40

    /// The dash phase `time` seconds in. It falls, so the dashes run forward along the
    /// outline, which goes clockwise.
    static func phase(at time: TimeInterval) -> CGFloat {
        -(CGFloat(time) * speed).truncatingRemainder(dividingBy: dash + gap)
    }

    var body: some View {
        Group {
            if frozenAt == nil, !reduceMotion {
                MarchingRim(radii: radii, dockedEdges: dockedEdges)
            } else {
                UnevenRoundedRectangle(
                    topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
                    bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
                    style: .continuous)
                    .strokeBorder(
                        AgentPalette.compacting,
                        style: StrokeStyle(
                            lineWidth: Self.lineWidth, dash: [Self.dash, Self.gap],
                            dashPhase: Self.phase(at: frozenAt ?? 0)))
                    .mask { Rectangle().padding(edgeInsets) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Hides the line on the edges that touch the screen: a notch has no line there.
    private var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: dockedEdges.contains(.top) ? 3 : 0,
            leading: dockedEdges.contains(.left) ? 3 : 0,
            bottom: dockedEdges.contains(.bottom) ? 3 : 0,
            trailing: dockedEdges.contains(.right) ? 3 : 0)
    }
}

/// The live dashed line: one shape layer whose dash phase Core Animation moves.
private struct MarchingRim: NSViewRepresentable {
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>

    func makeNSView(context: Context) -> RimView { RimView() }

    func updateNSView(_ view: RimView, context: Context) {
        view.configure(radii: radii, dockedEdges: dockedEdges)
    }

    final class RimView: NSView {
        private let line = CAShapeLayer()
        private let cut = CALayer()
        private var radii: IslandCornerRadii?
        private var dockedEdges: Set<ScreenEdge> = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            line.fillColor = nil
            line.strokeColor = NSColor(AgentPalette.compacting).cgColor
            line.lineWidth = CompactingRim.lineWidth
            line.lineDashPattern = [
                NSNumber(value: Double(CompactingRim.dash)), NSNumber(value: Double(CompactingRim.gap)),
            ]
            cut.backgroundColor = NSColor.black.cgColor
            line.mask = cut
            layer?.addSublayer(line)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>) {
            if self.radii != radii || self.dockedEdges != dockedEdges {
                self.radii = radii
                self.dockedEdges = dockedEdges
                needsLayout = true
            }
            startMarching()
        }

        override func layout() {
            super.layout()
            guard let radii else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            line.frame = bounds
            cut.frame = Self.uncut(bounds, docked: dockedEdges)
            let inset = CompactingRim.lineWidth / 2
            line.path = Self.outline(in: bounds.insetBy(dx: inset, dy: inset), radii: radii)
            CATransaction.commit()
            startMarching()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                line.removeAnimation(forKey: "march")
            } else {
                startMarching()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            line.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func startMarching() {
            guard window != nil, line.animation(forKey: "march") == nil else { return }
            let period = CompactingRim.dash + CompactingRim.gap
            let march = CABasicAnimation(keyPath: "lineDashPhase")
            march.fromValue = 0
            march.toValue = -period
            march.duration = Double(period / CompactingRim.speed)
            march.repeatCount = .infinity
            march.timingFunction = CAMediaTimingFunction(name: .linear)
            march.isRemovedOnCompletion = false
            line.add(march, forKey: "march")
        }

        /// What the line may show: the bounds less 3 pt along each edge against the screen.
        /// Layer coordinates run upward, so the top edge is at `maxY`.
        private static func uncut(_ bounds: CGRect, docked: Set<ScreenEdge>) -> CGRect {
            var rect = bounds
            if docked.contains(.top) { rect.size.height -= 3 }
            if docked.contains(.bottom) { rect.origin.y += 3; rect.size.height -= 3 }
            if docked.contains(.left) { rect.origin.x += 3; rect.size.width -= 3 }
            if docked.contains(.right) { rect.size.width -= 3 }
            return rect
        }

        /// The island's outline, clockwise as seen on screen, starting at the left end of the
        /// top edge. Layer coordinates run upward: the top edge is at `maxY`.
        private static func outline(in rect: CGRect, radii: IslandCornerRadii) -> CGPath {
            let half = min(rect.width, rect.height) / 2
            let topLeading = min(radii.topLeading, half)
            let topTrailing = min(radii.topTrailing, half)
            let bottomTrailing = min(radii.bottomTrailing, half)
            let bottomLeading = min(radii.bottomLeading, half)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.maxX - topTrailing, y: rect.maxY - topTrailing), radius: topTrailing,
                startAngle: .pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bottomTrailing))
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomTrailing, y: rect.minY + bottomTrailing),
                radius: bottomTrailing, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeading, y: rect.minY + bottomLeading),
                radius: bottomLeading, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - topLeading))
            path.addArc(
                center: CGPoint(x: rect.minX + topLeading, y: rect.maxY - topLeading), radius: topLeading,
                startAngle: .pi, endAngle: .pi / 2, clockwise: true)
            path.closeSubpath()
            return path
        }
    }
}
