import SwiftUI
import SymbiodockCore

/// A player's own volume as a thin vertical bar: full at the top. Dragging anywhere in
/// its column sets the level.
struct VolumeSlider: View {
    let target: VolumeTarget
    /// The player's volume, 0...1.
    let value: Double
    let onChange: (Double) -> Void

    @Environment(IslandGeometry.self) private var geometry: IslandGeometry?
    /// The level under the pointer while it is dragged; the player follows a little behind.
    @State private var dragged: Double?
    @State private var lastSent = Date.distantPast

    /// An Apple Event per pointer move would make the drag stutter.
    private static let sendInterval: TimeInterval = 0.06
    static let width: CGFloat = 18
    /// Bar and glyph together. A taller column gets no longer bar: the slider stays in
    /// proportion to the rows beside it and is centred by whoever lays it out.
    static let maxHeight: CGFloat = 72

    private var shown: Double { dragged ?? value }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(height: max(proxy.size.height * shown, 6))
                }
                .frame(width: 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let level = VolumeLevel.fraction(
                                atY: gesture.location.y, height: proxy.size.height)
                            dragged = level
                            guard Date().timeIntervalSince(lastSent) >= Self.sendInterval else { return }
                            lastSent = Date()
                            onChange(level)
                        }
                        .onEnded { gesture in
                            onChange(
                                VolumeLevel.fraction(atY: gesture.location.y, height: proxy.size.height))
                            dragged = nil
                        })
            }
            Image(systemName: glyph)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 9)
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight)
        // A press here moves the level, not the island.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        geometry?.noDragRects[target.rawValue] = frame.insetBy(dx: -4, dy: -4)
                    }
            }
        }
        .onDisappear { geometry?.noDragRects[target.rawValue] = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(target.applicationName) volume")
        .accessibilityValue("\(VolumeLevel.percent(shown)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.1, 1))
            case .decrement: onChange(max(value - 0.1, 0))
            @unknown default: break
            }
        }
    }

    private var glyph: String {
        switch shown {
        case ...0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
