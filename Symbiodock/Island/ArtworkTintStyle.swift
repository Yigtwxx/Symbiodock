import SwiftUI
import SymbiodockCore

extension TintColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// What the filled part of a bar is made of: the colours of the cover of what plays, as one
/// run from its start to its end, or white where the cover has no colour to give. The whole
/// run always shows, however little of the bar is filled.
struct BarFill: View {
    let tint: ArtworkTint?
    /// Left to right, or bottom to top.
    var isVertical = false

    var body: some View {
        if let tint {
            LinearGradient(
                colors: tint.stops.map(\.color),
                startPoint: isVertical ? .bottom : .leading,
                endPoint: isVertical ? .top : .trailing)
        } else {
            Color.white.opacity(0.9)
        }
    }
}
