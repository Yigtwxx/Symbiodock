import Foundation

/// The finish seal: a finished session's pet is framed the way Face ID frames a face, the
/// frame closes into a circle as the pet fades, and a check is drawn in the circle. Pure
/// functions of time, so the views only draw. Spec:
/// `2026-11-15-finish-seal-and-compacting-design.md`, section 4.1.
public enum AgentSealTiming {
    /// The whole seal; the session settles when it is over.
    public static let duration: TimeInterval = 1.7
    /// How long the still seal shows with Reduce Motion.
    public static let stillDuration: TimeInterval = 1.0
    /// The frame has closed in on the pet.
    public static let framed: TimeInterval = 0.45
    /// The frame has become a circle and the pet has gone.
    public static let rounded: TimeInterval = 0.75
    /// The check is drawn; the seal holds from here until `duration`.
    public static let checked: TimeInterval = 1.15

    /// How large the frame starts, relative to the pet.
    public static let frameStart = 1.25
    /// How much the pet shrinks while it fades.
    public static let petShrink = 0.10
    /// How much the circle swells while the check lands.
    public static let pop = 0.08

    /// One moment of the seal.
    public struct Pose: Equatable, Sendable {
        /// The frame's side relative to the pet's.
        public var frameScale: Double
        /// 0: four corner brackets; 1: a closed circle.
        public var roundness: Double
        public var petOpacity: Double
        public var petScale: Double
        /// 0: the frame is white; 1: it is mint.
        public var mint: Double
        /// How much of the check is drawn, 0...1.
        public var check: Double
        /// The frame and check's scale: 1, swelling a little while the check lands.
        public var swell: Double
    }

    /// The seal `time` seconds after it began. Before 0 it is at its start; from `checked`
    /// on it is at its end.
    public static func pose(at time: TimeInterval) -> Pose {
        let closing = ease(progress(time, from: 0, to: framed))
        let rounding = ease(progress(time, from: framed, to: rounded))
        let checking = progress(time, from: rounded, to: checked)
        return Pose(
            frameScale: frameStart - (frameStart - 1) * closing,
            roundness: rounding,
            petOpacity: 1 - rounding,
            petScale: 1 - petShrink * rounding,
            mint: ease(min(checking * 2, 1)),
            check: ease(checking),
            swell: 1 + pop * sin(.pi * checking))
    }

    /// The seal as it ends: what Reduce Motion shows, still.
    public static var finalPose: Pose { pose(at: checked) }

    private static func progress(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        min(max((time - start) / (end - start), 0), 1)
    }

    /// Starts and ends gently.
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
