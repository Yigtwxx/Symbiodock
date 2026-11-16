import AppKit

/// The trackpad's tick, for moments the pointer should feel: a tear, a catch, a drop.
enum Haptics {
    /// The firmest pattern AppKit offers; `.alignment` was too faint to notice. Felt on the
    /// trackpad only; a mouse has nothing to move.
    @MainActor
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
