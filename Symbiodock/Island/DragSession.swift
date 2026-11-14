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
    private var targetSize: CGSize = .zero
    private var rootScale: CGFloat = 1
    private var lastStep: Date?

    /// Starts a drag of an island that rests at `restingFrame`, attached to `rootRect`.
    /// - Parameters:
    ///   - rootAtNotch: the root is the notch, so its top is flush with the display edge.
    ///   - rootIsPhysicalNotch: the root is real hardware and stays after the island leaves;
    ///     any other root is the island's old place and shrinks away once the goo tears.
    func begin(restingFrame: CGRect, rootRect: CGRect, rootAtNotch: Bool, rootIsPhysicalNotch: Bool) {
        var configuration = SymbioteSimulation.Configuration()
        configuration.rootSpread = CGSize(width: rootRect.width * 0.33, height: rootRect.height * 0.22)
        configuration.islandSpread = CGSize(
            width: restingFrame.width * 0.35, height: restingFrame.height * 0.25)
        simulation = SymbioteSimulation(configuration: configuration)

        self.rootRect = rootRect
        rootHasSquareTop = rootAtNotch
        rootOutlivesTheTear = rootIsPhysicalNotch
        restCenter = CGPoint(x: restingFrame.midX, y: restingFrame.midY)
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
        bodyCenter = CGPoint(x: restCenter.x + offset.width, y: restCenter.y + offset.height)
    }

    /// The island came off: every strand breaks, and the body becomes a free-floating capsule.
    func tear() {
        simulation.tear()
        targetSize = IslandLayout.floatingCollapsedSize
    }

    /// The pointer let go: glide into `frame`.
    func settle(into frame: CGRect) {
        targetCenter = CGPoint(x: frame.midX, y: frame.midY)
        targetSize = frame.size
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
            }
        }
        if simulation.isTorn, !rootOutlivesTheTear {
            rootScale = max(0, rootScale - CGFloat(dt / Self.rootShrinkTime))
        }

        let rootCenter = CGPoint(x: rootRect.midX, y: rootRect.midY)
        simulation.advance(root: rootCenter, island: bodyCenter, dt: dt)

        let bodyFrame = CGRect(
            x: bodyCenter.x - bodySize.width / 2, y: bodyCenter.y - bodySize.height / 2,
            width: bodySize.width, height: bodySize.height)
        let island = Path(
            roundedRect: bodyFrame, cornerRadius: min(bodySize.height / 2, 18), style: .continuous)
        let bounds = rootRect.union(bodyFrame).insetBy(dx: -Self.padding, dy: -Self.padding)
        return Snapshot(goo: simulation.frame, root: rootPath(), island: island, bounds: bounds)
    }

    private func rootPath() -> Path {
        guard rootScale > 0.02 else { return Path() }
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
