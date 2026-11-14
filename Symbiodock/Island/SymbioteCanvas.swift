import SwiftUI
import SymbiodockCore

/// Draws one frame of the symbiote effect: the goo strands and the two bodies they join.
///
/// Two layers. Underneath, strands and bodies go through blur + alpha threshold (the
/// metaball trick), which webs neighbouring strands together where they leave a body.
/// On top, the same strands and the bodies are drawn crisp: the filter alone swallows
/// anything thinner than its blur and rounds the bodies' corners.
struct SymbioteCanvas: View {
    let frame: SymbioteFrame
    /// The shape the island was attached to (the notch, or its old place at an edge).
    let root: Path
    let island: Path
    /// Where this canvas sits in the coordinate space the shapes are given in.
    /// The canvas covers only the area around the drag, not the whole display.
    var origin: CGPoint = .zero

    private static let blurRadius: CGFloat = 5

    var body: some View {
        // Built once per frame and filled in both layers.
        let strands = strandPaths()
        let ribbons = strands.ribbons.offsetBy(dx: -origin.x, dy: -origin.y)
        let droplets = strands.droplets.offsetBy(dx: -origin.x, dy: -origin.y)
        let root = root.offsetBy(dx: -origin.x, dy: -origin.y)
        let island = island.offsetBy(dx: -origin.x, dy: -origin.y)
        return Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            context.drawLayer { goo in
                // Added first, applied last: blur, then cut the soft edge back to a hard one.
                goo.addFilter(.alphaThreshold(min: 0.5, color: .black))
                goo.addFilter(.blur(radius: Self.blurRadius))
                goo.drawLayer { layer in
                    layer.fill(ribbons, with: .color(.black))
                    layer.fill(droplets, with: .color(.black))
                    layer.fill(root, with: .color(.black))
                    layer.fill(island, with: .color(.black))
                }
            }
            context.fill(ribbons, with: .color(.black))
            context.fill(droplets, with: .color(.black))
            context.fill(root, with: .color(.black))
            context.fill(island, with: .color(.black))
        }
        .allowsHitTesting(false)
    }

    /// Ribbons and droplets as one path each. Kept apart because a nonzero fill can punch a hole
    /// where shapes of opposite winding overlap, and a droplet overlaps its stub.
    private func strandPaths() -> (ribbons: Path, droplets: Path) {
        var ribbons = Path()
        for polygon in frame.ribbons {
            ribbons.addLines(polygon)
            ribbons.closeSubpath()
        }
        var droplets = Path()
        for droplet in frame.droplets {
            droplets.addEllipse(in: CGRect(
                x: droplet.center.x - droplet.radius, y: droplet.center.y - droplet.radius,
                width: droplet.radius * 2, height: droplet.radius * 2))
        }
        return (ribbons, droplets)
    }
}
