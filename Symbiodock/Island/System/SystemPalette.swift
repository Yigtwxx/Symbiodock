import AppKit
import SwiftUI
import SymbiodockCore

/// The colours of the System tab: each measure has its own, the owner's choice from the
/// mockup. None says "good" or "bad"; only a temperature's number changes colour with heat.
@MainActor
enum SystemPalette {
    /// Left to right along the bar.
    static let cpu = [rgb(0x2F7BFF), rgb(0x5EE7FF)]
    static let gpu = [rgb(0xA45CFF), rgb(0xFF7EDB)]
    static let ram = [rgb(0x34D17A), rgb(0xC6F56B)]

    static let down = Color(nsColor: rgb(0x7CF5C8))
    /// What the area under the download line fades to.
    static let downFade = Color(nsColor: rgb(0x2BD4A4))
    static let up = Color(nsColor: rgb(0xFFB86B))

    static func color(for tier: TemperatureTier) -> Color {
        switch tier {
        case .normal: .white.opacity(0.55)
        case .warm: Color(nsColor: rgb(0xFFD60A))
        case .hot: Color(nsColor: rgb(0xFF6B5E))
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
