import SwiftUI
import SymbiodockCore

/// The goo that swallows a tile while its file changes format: strands reach in from the
/// tile's edges and close over it, it holds as a black cocoon while the file converts, then
/// the cover tears in the middle and pulls back to the edges over the changed tile
/// (`SymbioteEngulf`, timed by `EngulfTiming`). Drawn by the drag effect's canvas, so it is
/// the notch's goo.
///
/// It redraws frame by frame only while it closes or opens. The closed cocoon is drawn once
/// and only its glints breathe, run by Core Animation; once open it draws nothing. Its own
/// size is the tile's; the goo spills `SymbioteEngulf.overhang` past it on every side.
struct EngulfView: View {
    let size: CGSize
    let conversion: FileConversion
    /// Draws this phase and never moves; for renders.
    var frozen: EngulfPhase? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The part of the effect that plays now, moved on at each boundary of the clock.
    @State private var stretch: Stretch

    /// The cocoon's glints dim to this share of their light and back, once a breath.
    private static let dimmestGlint: Float = 0.45
    private static let breathPeriod: TimeInterval = 2.8

    private static var overhang: CGFloat { SymbioteEngulf.overhang }

    /// What the view shows between two boundaries of the clock.
    private enum Stretch: Equatable {
        /// Closing or opening: drawn on every frame.
        case moving
        /// Closed: drawn once.
        case still
        /// Open again: nothing to draw.
        case over
    }

    init(size: CGSize, conversion: FileConversion, frozen: EngulfPhase? = nil) {
        self.size = size
        self.conversion = conversion
        self.frozen = frozen
        _stretch = State(initialValue: Self.stretch(of: conversion, at: Date()))
    }

    var body: some View {
        Group {
            if reduceMotion {
                FadingCover(size: size, conversion: conversion)
            } else if let frozen {
                if frozen == .cocoon { cocoon } else { goo(SymbioteEngulf.frame(size: size, phase: frozen)) }
            } else {
                switch stretch {
                case .moving:
                    TimelineView(.animation) { context in
                        let phase = Self.phase(of: conversion, at: context.date)
                        goo(SymbioteEngulf.frame(size: size, phase: phase))
                    }
                case .still:
                    cocoon
                case .over:
                    Color.clear
                }
            }
        }
        .frame(width: size.width + 2 * Self.overhang, height: size.height + 2 * Self.overhang)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: conversion) {
            // Sleeps to the end of the closing, or of the opening once it has begun; a new
            // reveal time restarts it. A cocoon waits for that without a timer.
            guard frozen == nil else { return }
            while !Task.isCancelled {
                let now = Date()
                let current = Self.stretch(of: conversion, at: now)
                if stretch != current { stretch = current }
                guard let boundary = Self.boundary(of: conversion, after: now) else { return }
                try? await Task.sleep(for: .seconds(boundary.timeIntervalSince(now)))
            }
        }
    }

    /// The closed cover drawn once, its glints apart in a layer whose opacity breathes.
    private var cocoon: some View {
        let frame = SymbioteEngulf.frame(size: size, phase: .cocoon)
        return ZStack {
            goo(SymbioteFrame(ribbons: frame.ribbons, droplets: frame.droplets))
            Breathing(dimmest: Self.dimmestGlint, period: Self.breathPeriod) {
                // No ribbons: the canvas then skips its goo layer and draws only the glints.
                goo(SymbioteFrame(highlights: frame.highlights))
            }
        }
    }

    private func goo(_ frame: SymbioteFrame) -> some View {
        SymbioteCanvas(
            frame: frame, root: Path(), island: Path(),
            origin: CGPoint(x: -Self.overhang, y: -Self.overhang))
    }

    private static func phase(of conversion: FileConversion, at date: Date) -> EngulfPhase {
        EngulfTiming.phase(
            elapsed: date.timeIntervalSince(conversion.started),
            revealElapsed: conversion.revealStarted.map { date.timeIntervalSince($0) })
    }

    private static func stretch(of conversion: FileConversion, at date: Date) -> Stretch {
        switch phase(of: conversion, at: date) {
        case .engulf, .reveal: .moving
        case .cocoon: .still
        case .done: .over
        }
    }

    /// When the stretch playing at `date` ends; nil while it lasts until the conversion changes.
    private static func boundary(of conversion: FileConversion, after date: Date) -> Date? {
        let end = conversion.revealStarted.map { $0.addingTimeInterval(EngulfTiming.reveal) }
            ?? conversion.started.addingTimeInterval(EngulfTiming.engulf)
        return end > date ? end : nil
    }
}

/// With Reduce Motion the tile only darkens to black and clears again, `stillFade` each way.
private struct FadingCover: View {
    let size: CGSize
    let conversion: FileConversion

    @State private var hasDarkened = false

    var body: some View {
        let isCovered = hasDarkened && conversion.revealStarted == nil
        RoundedRectangle(cornerRadius: CardGlass.radius, style: .continuous)
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .opacity(isCovered ? 1 : 0)
            .animation(.easeInOut(duration: EngulfTiming.stillFade), value: isCovered)
            .onAppear { hasDarkened = true }
    }
}

extension EnvironmentValues {
    /// Freezes every engulf below at this phase; for renders of whole pages.
    @Entry var frozenEngulf: EngulfPhase? = nil
}
