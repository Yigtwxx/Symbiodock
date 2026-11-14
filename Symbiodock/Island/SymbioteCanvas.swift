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

    private static let blurRadius: CGFloat = 5

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            context.drawLayer { goo in
                // Added first, applied last: blur, then cut the soft edge back to a hard one.
                goo.addFilter(.alphaThreshold(min: 0.5, color: .black))
                goo.addFilter(.blur(radius: Self.blurRadius))
                goo.drawLayer { layer in
                    drawStrands(in: &layer)
                    layer.fill(root, with: .color(.black))
                    layer.fill(island, with: .color(.black))
                }
            }
            drawStrands(in: &context)
            context.fill(root, with: .color(.black))
            context.fill(island, with: .color(.black))
        }
        .allowsHitTesting(false)
    }

    private func drawStrands(in context: inout GraphicsContext) {
        for polygon in frame.ribbons {
            var path = Path()
            path.addLines(polygon)
            path.closeSubpath()
            context.fill(path, with: .color(.black))
        }
        for droplet in frame.droplets {
            let rect = CGRect(
                x: droplet.center.x - droplet.radius, y: droplet.center.y - droplet.radius,
                width: droplet.radius * 2, height: droplet.radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.black))
        }
    }
}
