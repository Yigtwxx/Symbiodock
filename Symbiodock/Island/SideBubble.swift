import SwiftUI
import SymbiodockCore

/// The round bubble beside the collapsed island: the face of the tab the island itself is
/// not showing. Music is its artwork as a disc, with a second source as a smaller disc
/// showing behind it on the left; an agent is its pet.
struct SideBubble: View {
    enum Content {
        case media(front: NowPlayingInfo, behind: NowPlayingInfo?)
        case agent(AgentRow)
    }

    let content: Content
    let diameter: CGFloat

    /// Black kept around the artwork, so that it reads as a bubble and not as a cut-out.
    private static let rim: CGFloat = 3

    var body: some View {
        let small = diameter * IslandLayout.bubbleBehindScale
        let peek = IslandLayout.bubblePeek(diameter: diameter)

        ZStack(alignment: .trailing) {
            if case .media(_, let behind?) = content {
                disc(small) {
                    ArtworkView(
                        data: behind.artworkData,
                        size: small - 2 * Self.rim * IslandLayout.bubbleBehindScale, isRound: true)
                        .opacity(0.7)
                }
                .padding(.trailing, diameter - small + peek)
                .transition(.opacity.combined(with: .offset(x: peek)))
            }
            disc(diameter) {
                switch content {
                case .media(let front, _):
                    ArtworkView(data: front.artworkData, size: diameter - 2 * Self.rim, isRound: true)
                case .agent(let row):
                    AgentFacePet(row: row, size: (diameter * 0.64).rounded())
                }
            }
        }
        // The disc behind hangs out on the left; the bubble's own frame is the front disc.
        .frame(width: diameter, height: diameter, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasBehind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var hasBehind: Bool {
        if case .media(_, _?) = content { true } else { false }
    }

    private var label: String {
        switch content {
        case .media(let front, _): "Now playing, \(front.title)"
        case .agent(let row): AgentFaceLabel.text(for: row)
        }
    }

    private func disc(_ size: CGFloat, @ViewBuilder _ inside: () -> some View) -> some View {
        inside()
            .frame(width: size, height: size)
            .background(.black, in: Circle())
            .clipShape(Circle())
    }
}
