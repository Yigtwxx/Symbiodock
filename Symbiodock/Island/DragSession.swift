import SwiftUI
import SymbiodockCore

/// Everything that moves while the island is dragged or settling: its body, the goo that
/// ties it to the place it was attached, and the strands it throws at a surface it nears.
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
    /// After the release the strands that hold a surface are soaked back up over this span
    /// (seconds since the release); it ends before `OverlayController.settleDuration`.
    private static let soakStart = 0.2
    private static let soakEnd = 0.45
    /// Sets of torn strands still snapping back, beside the set holding now. Each lasts
    /// about 0.7 s and a fast slide along an edge tears one loose every 130 pt.
    private static let maxFadingReaches = 8
    /// Strands shorter than this are hidden inside the island: no tick for a catch nobody sees.
    private static let visibleCatchDistance: CGFloat = 6

    /// Strands thrown at a surface, and the fixed place where they took hold of it.
    private struct Reach {
        var surface: IslandSurface
        var root: CGPoint
        var simulation: SymbioteSimulation
        var hasCaught = false
    }

    /// Called when the main strand takes hold of a surface while the island is carried.
    var onCatch: (() -> Void)?

    private var simulation = SymbioteSimulation()
    private var reach: Reach?
    private var fadingReaches: [Reach] = []
    /// The island has come off its root; only then does it reach for somewhere new.
    private var isTornOff = false
    private var notch: CGRect = .zero
    private var visibleFrame: CGRect = .zero
    private var hasPhysicalNotch = false
    /// Where the released island is going; strands are thrown only at that place.
    private var settleAnchor: IslandAnchor?
    private var settleElapsed = 0.0
    private var rootRect: CGRect = .zero
    /// Where the island rested when the drag began; the root keeps that place's outline.
    private var rootAnchor: IslandAnchor = .notch
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
    /// From the resting center to where the island's middle was when it was grabbed
    /// (it may have been expanded); eases to nothing so the grab does not make it jump.
    private var startOffset: CGSize = .zero
    private var startBlend: CGFloat = 0
    private var startBlendVelocity: CGFloat = 0
    private var settleDistance: CGFloat = 0
    private var targetSize: CGSize = .zero
    private var rootScale: CGFloat = 1
    private var lastStep: Date?

    /// Starts a drag of an island that rests at `restingFrame`, attached to `rootRect`.
    /// - Parameters:
    ///   - rootAnchor: where the island rests; the root has that place's outline.
    ///   - rootIsPhysicalNotch: the root is real hardware and stays after the island leaves;
    ///     any other root is the island's old place and shrinks away once the goo tears.
    ///   - notch, visibleFrame, hasPhysicalNotch: the surfaces the carried island can reach for.
    /// - Parameter currentFrame: the island as it is on screen at the grab; it shrinks from
    ///   there to `restingFrame`, the collapsed island that is actually dragged.
    func begin(
        currentFrame: CGRect, restingFrame: CGRect, press: CGPoint, rootRect: CGRect,
        rootAnchor: IslandAnchor, rootIsPhysicalNotch: Bool,
        notch: CGRect, visibleFrame: CGRect, hasPhysicalNotch: Bool
    ) {
        self.notch = notch
        self.visibleFrame = visibleFrame
        self.hasPhysicalNotch = hasPhysicalNotch
        reach = nil
        fadingReaches = []
        isTornOff = false
        settleAnchor = nil
        settleElapsed = 0
        var configuration = SymbioteSimulation.Configuration()
        configuration.rootSpread = CGSize(width: rootRect.width * 0.33, height: rootRect.height * 0.22)
        configuration.islandSpread = CGSize(
            width: restingFrame.width * 0.35, height: restingFrame.height * 0.25)
        simulation = SymbioteSimulation(configuration: configuration)

        self.rootRect = rootRect
        self.rootAnchor = rootAnchor
        rootOutlivesTheTear = rootIsPhysicalNotch
        restCenter = CGPoint(x: restingFrame.midX, y: restingFrame.midY)
        grabOffset = CGSize(width: press.x - restCenter.x, height: press.y - restCenter.y)
        pointerOffset = .zero
        grabBlend = 0
        grabBlendVelocity = 0
        startOffset = CGSize(
            width: currentFrame.midX - restCenter.x, height: currentFrame.midY - restCenter.y)
        startBlend = 1
        startBlendVelocity = 0
        bodySize = currentFrame.size
        placeBody()
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
            x: restCenter.x + pointerOffset.width + grabOffset.width * grabBlend
                + startOffset.width * startBlend,
            y: restCenter.y + pointerOffset.height + grabOffset.height * grabBlend
                + startOffset.height * startBlend)
    }

    /// The island came off: every strand breaks, and the body becomes a free-floating capsule.
    func tear() {
        simulation.tear()
        targetSize = IslandLayout.floatingCollapsedSize
        isTornOff = true
    }

    /// The surface the island's strands are holding or reaching for: released now, it goes there.
    var heldSurface: IslandSurface? {
        guard let reach, !reach.simulation.isTorn else { return nil }
        return reach.surface
    }

    /// True once the main strand has taken hold of `heldSurface` (the tick has been given).
    var hasCaughtSurface: Bool {
        heldSurface != nil && reach?.hasCaught == true
    }

    /// The pointer let go: glide into `frame`, the island's place at `anchor`.
    func settle(into frame: CGRect, anchor: IslandAnchor) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        targetCenter = center
        targetSize = frame.size
        settleDistance = max(hypot(center.x - bodyCenter.x, center.y - bodyCenter.y), 1)
        settleAnchor = anchor
        settleElapsed = 0
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
            } else {
                Self.spring(&startBlend, &startBlendVelocity, toward: 0, h)
                if simulation.isTorn {
                    Self.spring(&grabBlend, &grabBlendVelocity, toward: 1, h)
                }
            }
        }
        // Wall-clock, not the clamped step: a hitch must not leave strands behind when the
        // resting island takes over.
        if targetCenter == nil { placeBody() } else { settleElapsed += max(elapsed, 0) }
        if simulation.isTorn, !rootOutlivesTheTear {
            rootScale = max(0, rootScale - CGFloat(dt / Self.rootShrinkTime))
        }

        let rootCenter = CGPoint(x: rootRect.midX, y: rootRect.midY)
        // The goo is stretched by how far the island has been pulled, not by the body easing
        // down from an expanded grab: otherwise strands would tear before the island does.
        let pulled = targetCenter == nil
            ? CGPoint(
                x: bodyCenter.x - startOffset.width * startBlend,
                y: bodyCenter.y - startOffset.height * startBlend)
            : bodyCenter
        simulation.advance(root: rootCenter, island: pulled, dt: dt)

        let bodyFrame = CGRect(
            x: bodyCenter.x - bodySize.width / 2, y: bodyCenter.y - bodySize.height / 2,
            width: bodySize.width, height: bodySize.height)
        var goo = simulation.frame
        let reachGoo = stepReaches(body: bodyFrame, dt: dt)
        // Once the goo is gone a physical notch has nothing left to draw: stop covering it,
        // or the canvas would span from the notch to wherever the island is carried.
        let rootIsDrawn = rootScale > 0.02 && !(rootOutlivesTheTear && simulation.isFinished)
        var area = bodyFrame
        if rootIsDrawn || !goo.isEmpty { area = area.union(rootRect) }
        if let box = reachGoo.boundingBox { area = area.union(box) }
        goo.append(reachGoo)
        let bounds = area.insetBy(dx: -Self.padding, dy: -Self.padding).integral
        return Snapshot(
            goo: goo, root: rootIsDrawn ? rootPath() : Path(), island: islandPath(bodyFrame),
            bounds: bounds)
    }

    // MARK: Reaching

    /// Throws strands at a surface that has come within reach, keeps the ones already holding
    /// in step with the island, and returns everything they draw.
    private func stepReaches(body: CGRect, dt: Double) -> SymbioteFrame {
        guard isTornOff else { return SymbioteFrame() }

        // The main strand gave way: what is left only snaps back, and the island may reach again.
        if let current = reach, current.simulation.isTorn {
            retire(current)
            reach = nil
        }
        if let target = ReachResolver.target(
            body: body, notch: notch, notchIsPhysical: hasPhysicalNotch, visibleFrame: visibleFrame),
            accepts(target.surface) {
            if let current = reach {
                // The notch takes the island over from the edge beside it.
                if target.surface == .notch, current.surface != .notch {
                    var released = current
                    released.simulation.tear()
                    retire(released)
                    reach = makeReach(target, body: body)
                }
            } else {
                reach = makeReach(target, body: body)
            }
        }

        // A landed island soaks its strands back up.
        let soak = targetCenter == nil
            ? 1 : 1 - Self.smoothstep(Self.soakStart, Self.soakEnd, settleElapsed)
        var goo = SymbioteFrame()
        /// Returns how long the strands are after the step.
        @discardableResult
        func advance(_ reach: inout Reach) -> CGFloat {
            let point = ReachResolver.islandPoint(
                body: body, surface: reach.surface, visibleFrame: visibleFrame)
            reach.simulation.thickness = CGFloat(soak)
            reach.simulation.advance(root: reach.root, island: point, dt: dt)
            goo.append(reach.simulation.frame)
            return hypot(point.x - reach.root.x, point.y - reach.root.y)
        }
        if var current = reach {
            let length = advance(&current)
            // An island pressed against the surface holds it with strands too short to see;
            // the catch is felt once they show.
            if current.simulation.isHolding, !current.hasCaught, length > Self.visibleCatchDistance {
                current.hasCaught = true
                if targetCenter == nil { onCatch?() }
            }
            reach = current
        }
        for index in fadingReaches.indices { advance(&fadingReaches[index]) }
        fadingReaches.removeAll { $0.simulation.isFinished }
        return goo
    }

    /// While carried the island reaches for whatever is near; once released, only for the
    /// place it is going to.
    private func accepts(_ surface: IslandSurface) -> Bool {
        guard targetCenter != nil else { return true }
        switch (settleAnchor, surface) {
        case (.notch?, .notch): return true
        case (.edge(let edge, _)?, .edge(let reached)): return edge == reached
        case (.corner(let corner)?, .edge(let reached)):
            switch corner {
            case .topLeft: return reached == .top || reached == .left
            case .topRight: return reached == .top || reached == .right
            case .bottomLeft: return reached == .bottom || reached == .left
            case .bottomRight: return reached == .bottom || reached == .right
            }
        default: return false
        }
    }

    private func makeReach(_ target: ReachTarget, body: CGRect) -> Reach {
        var configuration = SymbioteSimulation.Configuration()
        configuration.tearDistance = target.surface == .notch
            ? ReachResolver.notchTearDistance : ReachResolver.edgeTearDistance
        configuration.endRadius = 13
        configuration.islandSpread = CGSize(width: body.width * 0.35, height: body.height * 0.25)
        configuration.rootSpan = CGPoint(
            x: target.tangent.x * target.halfSpan, y: target.tangent.y * target.halfSpan)
        return Reach(
            surface: target.surface, root: target.root,
            simulation: SymbioteSimulation(configuration: configuration, reaching: true))
    }

    private func retire(_ reach: Reach) {
        var reach = reach
        // Strands still waiting to set off must not start from a set that has let go.
        reach.simulation.tear()
        guard !reach.simulation.isFinished else { return }
        fadingReaches.append(reach)
        if fadingReaches.count > Self.maxFadingReaches { fadingReaches.removeFirst() }
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Shapes

    /// A capsule while it is carried. On the way to its place it takes that place's outline
    /// (square against the screen edge, small free corners, like the notch), so nothing pops
    /// when the resting island takes over.
    private func islandPath(_ frame: CGRect) -> Path {
        let capsule = min(frame.height / 2, 18)
        guard let settleAnchor, let targetCenter else {
            return Path(roundedRect: frame, cornerRadius: capsule, style: .continuous)
        }
        let remaining = hypot(targetCenter.x - bodyCenter.x, targetCenter.y - bodyCenter.y)
        let arrival = min(max(1 - remaining / settleDistance, 0), 1)
        let docked = IslandLayout.cornerRadii(
            anchor: settleAnchor, radius: IslandLayout.collapsedCornerRadius)
        func blend(_ target: CGFloat) -> CGFloat { capsule + (target - capsule) * arrival }
        let radii = RectangleCornerRadii(
            topLeading: blend(docked.topLeading), bottomLeading: blend(docked.bottomLeading),
            bottomTrailing: blend(docked.bottomTrailing), topTrailing: blend(docked.topTrailing))
        return Path(roundedRect: frame, cornerRadii: radii, style: .continuous)
    }

    /// The place the island was pulled off, in that place's own outline. It shrinks toward
    /// the screen edge (or corner) it lies against, not toward its middle.
    private func rootPath() -> Path {
        let size = CGSize(width: rootRect.width * rootScale, height: rootRect.height * rootScale)
        let docked = IslandLayout.cornerRadii(
            anchor: rootAnchor, radius: IslandLayout.collapsedCornerRadius)
        // A side with two square corners lies on a screen edge: that side stays put.
        let onLeft = docked.topLeading == 0 && docked.bottomLeading == 0
        let onRight = docked.topTrailing == 0 && docked.bottomTrailing == 0
        let onTop = docked.topLeading == 0 && docked.topTrailing == 0
        let onBottom = docked.bottomLeading == 0 && docked.bottomTrailing == 0
        let rect = CGRect(
            x: onLeft ? rootRect.minX : onRight ? rootRect.maxX - size.width
                : rootRect.midX - size.width / 2,
            y: onTop ? rootRect.minY : onBottom ? rootRect.maxY - size.height
                : rootRect.midY - size.height / 2,
            width: size.width, height: size.height)
        let limit = min(rect.width, rect.height) / 2
        let radii = RectangleCornerRadii(
            topLeading: min(docked.topLeading, limit), bottomLeading: min(docked.bottomLeading, limit),
            bottomTrailing: min(docked.bottomTrailing, limit),
            topTrailing: min(docked.topTrailing, limit))
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
