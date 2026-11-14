import SwiftUI

/// The island while it is being dragged or settling: body, root and goo, redrawn every frame.
/// It exists only in those phases, so no per-frame work runs while the island rests.
struct DragLayer: View {
    let session: DragSession

    var body: some View {
        TimelineView(.animation) { timeline in
            let snapshot = session.step(to: timeline.date)
            SymbioteCanvas(
                frame: snapshot.goo, root: snapshot.root, island: snapshot.island,
                origin: snapshot.bounds.origin)
                .frame(width: snapshot.bounds.width, height: snapshot.bounds.height)
                .offset(x: snapshot.bounds.minX, y: snapshot.bounds.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
