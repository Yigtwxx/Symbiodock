import SwiftUI
import SymbiodockCore

/// The System tab: how busy and how warm this Mac is, and how fast its network.
struct SystemContent: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory
    /// The header band's height; the page starts below it.
    let topInset: CGFloat

    var body: some View {
        Color.clear
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
