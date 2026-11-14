import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let notch: CGRect

    var body: some View {
        GeometryReader { proxy in
            let frame = IslandLayout.frame(
                phase: state.phase, notch: notch, screenSize: proxy.size, hasTrack: state.hasTrack)
            let radius: CGFloat = state.phase == .expanded ? 24 : 10

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: 0,
                style: .continuous)
                .fill(.black)
                .overlay {
                    if state.phase == .expanded {
                        Text("Nothing playing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, notch.height)
                            .transition(.opacity)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.phase)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.hasTrack)
        }
        .ignoresSafeArea()
    }
}
