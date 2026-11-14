import SwiftUI
import SymbiodockCore

/// Everything that moves while the island is dragged or settling: its body and the goo
/// that ties it to the place it was attached.
///
/// Not observable on purpose. `DragLayer` asks for a snapshot once per display frame, so
/// nothing here invalidates views at pointer rate.
@MainActor
final class DragSession {
    struct Snapshot {
        var goo: SymbioteFrame
        var root: Path
        var island: Path
        /// The part of the panel the drawing needs; the canvas covers only this.
        var bounds: CGRect
    }

    private static let substep = 1.0 / 240
    private static let maxFrameTime = 1.0 / 30
    /// Room around the bodies for strands that whip sideways and for the goo layer's blur.
    private static let padding: CGFloat = 48
    private static let rootShrinkTime = 0.3

    private var simulation = SymbioteSimulation()
    private var rootRect: CGRect = .zero
    private var rootHasSquareTop = false
    private var rootOutlivesTheTear = false
    private var restCenter: CGPoint = .zero
    private(set) var bodyCenter: CGPoint = .zero
    private var bodySize: CGSize = .zero
    private var centerVelocity: CGPoint = .zero
    private var sizeVelocity: CGSize = .zero
    /// Nil while the pointer owns the position.
    private var targetCenter: CGPoint?
    /// From the island's resting center to where the pointer grabbed it.
    private var grabOffset: CGSize = .zero
    private var pointerOffset: CGSize = .zero
    /// 0 while attached; springs to 1 after the tear, bringing the body under the pointer.
    private var grabBlend: CGFloat = 0
    private var grabBlendVelocity: CGFloat = 0
    /// Set while settling into the notch: the capsule squares its top as it arrives.
    private var settlesIntoNotch = false
    private var settleDistance: CGFloat = 0
    private var targetSize: CGSize = .zero
    private var rootScale: CGFloat = 1
    private var lastStep: Date?

    /// Starts a drag of an island that rests at `restingFrame`, attached to `rootRect`.
    /// - Parameters:
    ///   - rootAtNotch: the root is the notch, so its top is flush with the display edge.
    ///   - rootIsPhysicalNotch: the root is real hardware and stays after the island leaves;
    ///     any other root is the island's old place and shrinks away once the goo tears.
    func begin(
        restingFrame: CGRect, press: CGPoint, rootRect: CGRect, rootAtNotch: Bool,
        rootIsPhysicalNotch: Bool
    ) {
        var configuration = SymbioteSimulation.Configuration()
        configuration.rootSpread = CGSize(width: rootRect.width * 0.33, height: rootRect.height * 0.22)
        configuration.islandSpread = CGSize(
            width: restingFrame.width * 0.35, height: restingFrame.height * 0.25)
        simulation = SymbioteSimulation(configuration: configuration)

        self.rootRect = rootRect
        rootHasSquareTop = rootAtNotch
        rootOutlivesTheTear = rootIsPhysicalNotch
        restCenter = CGPoint(x: restingFrame.midX, y: restingFrame.midY)
        grabOffset = CGSize(width: press.x - restCenter.x, height: press.y - restCenter.y)
        pointerOffset = .zero
        grabBlend = 0
        grabBlendVelocity = 0
        settlesIntoNotch = false
        bodyCenter = restCenter
        bodySize = restingFrame.size
        targetSize = restingFrame.size
        targetCenter = nil
        centerVelocity = .zero
        sizeVelocity = .zero
        rootScale = 1
        lastStep = nil
    }

    /// The pointer has moved this far since it grabbed the island.
    func move(by offset: CGSize) {
        guard targetCenter == nil else { return }
        pointerOffset = offset
        placeBody()
    }

    /// While attached the body moves as far as the pointer has; once torn off it also closes
    /// the gap to the pointer, so a grab at the island's corner ends with it under the pointer.
    private func placeBody() {
        bodyCenter = CGPoint(
            x: restCenter.x + pointerOffset.width + grabOffset.width * grabBlend,
            y: restCenter.y + pointerOffset.height + grabOffset.height * grabBlend)
    }

    /// The island came off: every strand breaks, and the body becomes a free-floating capsule.
    func tear() {
        simulation.tear()
        targetSize = IslandLayout.floatingCollapsedSize
    }

    /// The pointer let go: glide into `frame`.
    func settle(into frame: CGRect, atNotch: Bool) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        targetCenter = center
        targetSize = frame.size
        settlesIntoNotch = atNotch
        settleDistance = max(hypot(center.x - bodyCenter.x, center.y - bodyCenter.y), 1)
    }

    /// Advances to `date` and describes what to draw.
    func step(to date: Date) -> Snapshot {
        let elapsed = lastStep.map { date.timeIntervalSince($0) } ?? 0
        lastStep = date
        let dt = min(max(elapsed, 0), Self.maxFrameTime)

        var remaining = dt
        while remaining > 1e-9 {
            let h = min(remaining, Self.substep)
            remaining -= h
            Self.spring(&bodySize.width, &sizeVelocity.width, toward: targetSize.width, h)
            Self.spring(&bodySize.height, &sizeVelocity.height, toward: targetSize.height, h)
            if let targetCenter {
                Self.spring(&bodyCenter.x, &centerVelocity.x, toward: targetCenter.x, h)
                Self.spring(&bodyCenter.y, &centerVelocity.y, toward: targetCenter.y, h)
            } else if simulation.isTorn {
                Self.spring(&grabBlend, &grabBlendVelocity, toward: 1, h)
            }
        }
        if targetCenter == nil { placeBody() }
        if simulation.isTorn, !rootOutlivesTheTear {
            rootScale = max(0, rootScale - CGFloat(dt / Self.rootShrinkTime))
        }

        let rootCenter = CGPoint(x: rootRect.midX, y: rootRect.midY)
        simulation.advance(root: rootCenter, island: bodyCenter, dt: dt)

        let bodyFrame = CGRect(
            x: bodyCenter.x - bodySize.width / 2, y: bodyCenter.y - bodySize.height / 2,
            width: bodySize.width, height: bodySize.height)
        let goo = simulation.frame
        // Once the goo is gone a physical notch has nothing left to draw: stop covering it,
        // or the canvas would span from the notch to wherever the island is carried.
        let rootIsDrawn = rootScale > 0.02 && !(rootOutlivesTheTear && simulation.isFinished)
        var area = bodyFrame
        if rootIsDrawn || !goo.isEmpty { area = area.union(rootRect) }
        let bounds = area.insetBy(dx: -Self.padding, dy: -Self.padding).integral
        return Snapshot(
            goo: goo, root: rootIsDrawn ? rootPath() : Path(), island: islandPath(bodyFrame),
            bounds: bounds)
    }

    /// A capsule, except on the way into the notch, where it takes the notch's shape
    /// (square top, small bottom corners) so nothing pops when the resting island takes over.
    private func islandPath(_ frame: CGRect) -> Path {
        let capsule = min(frame.height / 2, 18)
        var arrival: CGFloat = 0
        if settlesIntoNotch, let targetCenter {
            let remaining = hypot(targetCenter.x - bodyCenter.x, targetCenter.y - bodyCenter.y)
            arrival = min(max(1 - remaining / settleDistance, 0), 1)
        }
        let top = capsule * (1 - arrival)
        let bottom = capsule + (10 - capsule) * arrival
        let radii = RectangleCornerRadii(
            topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top)
        return Path(roundedRect: frame, cornerRadii: radii, style: .continuous)
    }

    private func rootPath() -> Path {
        let size = CGSize(width: rootRect.width * rootScale, height: rootRect.height * rootScale)
        let rect = CGRect(
            x: rootRect.midX - size.width / 2,
            // A notch shrinks toward the display edge it hangs from, not toward its middle.
            y: rootHasSquareTop ? rootRect.minY : rootRect.midY - size.height / 2,
            width: size.width, height: size.height)
        let radius = min(rect.height / 2, rootHasSquareTop ? 10 : 18)
        let radii = RectangleCornerRadii(
            topLeading: rootHasSquareTop ? 0 : radius, bottomLeading: radius,
            bottomTrailing: radius, topTrailing: rootHasSquareTop ? 0 : radius)
        return Path(roundedRect: rect, cornerRadii: radii, style: .continuous)
    }

    /// A slightly underdamped spring: the body arrives quickly and overshoots just a little.
    private static func spring(
        _ value: inout CGFloat, _ velocity: inout CGFloat, toward target: CGFloat, _ h: Double
    ) {
        let omega = 2 * Double.pi * 3.2
        let acceleration = omega * omega * Double(target - value) - 2 * 0.78 * omega * Double(velocity)
        velocity += CGFloat(acceleration * h)
        value += velocity * CGFloat(h)
    }
}
