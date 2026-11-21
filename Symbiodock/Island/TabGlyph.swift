import SwiftUI
import SymbiodockCore

/// The glyph of a tab in the open island's strip. Drawn in code rather than taken from SF
/// Symbols, so that the three come from one hand: one 14-point grid, one 1.5-point stroke,
/// round ends and joins. The stock symbols, the "AI" sparkle above all, made the strip look
/// generated. Static: the outline is built once and nothing redraws at rest.
struct TabGlyph: View {
    let tab: IslandTab
    /// Larger only to inspect the drawing; the strip uses the grid's size.
    var size: CGFloat = TabGlyphOutline.grid

    var body: some View {
        GridOutline(outline: TabGlyphOutline.outline(for: tab))
            .frame(width: size, height: size)
    }
}

/// A filled outline drawn in grid units, scaled to its frame: the stroke scales with it, so
/// an enlarged glyph keeps its proportions.
private struct GridOutline: Shape {
    let outline: Path

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / TabGlyphOutline.grid
        return outline.applying(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.minX, ty: rect.minY))
    }
}

/// The four drawings, as filled outlines in grid units (y down).
///
/// Straight strokes run along quarter points (2.25, 10.75…): at 2x a 1.5-point stroke is
/// 3 pixels, and centred there it covers whole pixels instead of smearing over four.
enum TabGlyphOutline {
    /// The side of the square grid, in points.
    static let grid: CGFloat = 14
    static let lineWidth: CGFloat = 1.5
    /// The clear space where one part passes behind another. The part behind stops short with
    /// a round end, like every other end, instead of touching the part in front.
    static let gap: CGFloat = 1

    static func outline(for tab: IslandTab) -> Path {
        switch tab {
        case .agents: agents
        case .media: media
        case .system: system
        case .files: files
        }
    }

    /// A terminal prompt, `>_`: the agents are the tools working in terminals. The chevron
    /// is a right angle and its lower end sits on the underscore's line.
    static let agents = outline(of: [
        Part(polyline(CGPoint(x: 2.25, y: 3.25), CGPoint(x: 6, y: 7), CGPoint(x: 2.25, y: 10.75))),
        Part(polyline(CGPoint(x: 7.75, y: 10.75), CGPoint(x: 11.75, y: 10.75))),
    ])

    /// The level bars the closed island shows while something plays, caught mid-beat: four
    /// bars standing about the middle, as the island's own bars grow about their centres.
    static let media: Path = {
        var bars = Path()
        for (x, height) in zip([3.25, 5.75, 8.25, 10.75] as [CGFloat], [6, 10.5, 7.5, 4.5] as [CGFloat]) {
            // The heights are the ink's; the round caps add half a stroke at each end.
            let half = (height - lineWidth) / 2
            bars.move(to: CGPoint(x: x, y: 7 - half))
            bars.addLine(to: CGPoint(x: x, y: 7 + half))
        }
        return outline(of: [Part(bars)])
    }()

    /// Two held files: a sheet in front with its corner folded and the edge of one behind it.
    /// Both are tall like the shelf's cards. The fold is what makes them documents: plain
    /// rounded squares read as "copy" or a chain link, and a card with the top of another
    /// straight above it reads as a padlock or a bag.
    /// A chip: the processor the tab measures. A small rounded square with two legs on each
    /// side; the legs end on the square's own line, so they join it.
    static let system: Path = {
        var legs = Path()
        for at in [5.75, 8.25] as [CGFloat] {
            legs.move(to: CGPoint(x: at, y: 2.25))
            legs.addLine(to: CGPoint(x: at, y: 4.25))
            legs.move(to: CGPoint(x: at, y: 9.75))
            legs.addLine(to: CGPoint(x: at, y: 11.75))
            legs.move(to: CGPoint(x: 2.25, y: at))
            legs.addLine(to: CGPoint(x: 4.25, y: at))
            legs.move(to: CGPoint(x: 9.75, y: at))
            legs.addLine(to: CGPoint(x: 11.75, y: at))
        }
        return outline(of: [
            Part(card(x0: 4.25, y0: 4.25, x1: 9.75, y1: 9.75, folded: 0)),
            Part(legs),
        ])
    }()

    static let files = outline(of: [
        Part(card(x0: 5.75, y0: 2.25, x1: 11.25, y1: 9.25, folded: 0)),
        Part(card(x0: 2.75, y0: 4.75, x1: 8.25, y1: 11.75, folded: 2.25), hidesBehind: true),
    ])

    /// A stroked part of a drawing. Parts are listed back to front; one that hides what is
    /// behind it cuts the centre lines of the earlier parts, `gap` clear of its own ink.
    private struct Part {
        var path: Path
        var hidesBehind: Bool

        init(_ path: Path, hidesBehind: Bool = false) {
            self.path = path
            self.hidesBehind = hidesBehind
        }
    }

    /// Strokes the parts into one outline. Cutting the centre lines before stroking, rather
    /// than the finished ink, gives the cut ends round caps.
    private static func outline(of parts: [Part]) -> Path {
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        // The hidden region reaches past a part's centre line by half a stroke of its own ink,
        // the gap, and half a stroke for the cap of a line cut there.
        let reach = StrokeStyle(lineWidth: 2 * (lineWidth + gap), lineCap: .round, lineJoin: .round)
        var lines: [Path] = []
        for part in parts {
            if part.hidesBehind {
                let hidden = part.path.union(part.path.strokedPath(reach))
                lines = lines.map { $0.lineSubtraction(hidden) }
            }
            lines.append(part.path)
        }
        return lines.reduce(Path()) { $0.union($1.strokedPath(stroke)) }
    }

    private static func polyline(_ points: CGPoint...) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// A rounded sheet; with `folded` above zero its top right corner is folded over.
    private static func card(x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat, folded: CGFloat) -> Path {
        let radius: CGFloat = 1.25
        var path = Path()
        if folded > 0 {
            path.move(to: CGPoint(x: x1 - folded, y: y0))
            path.addLine(to: CGPoint(x: x1, y: y0 + folded))
        } else {
            path.move(to: CGPoint(x: (x0 + x1) / 2, y: y0))
            path.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y1), radius: radius)
        }
        path.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x0, y: y1), radius: radius)
        path.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y0), radius: radius)
        path.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x1, y: y0), radius: radius)
        path.closeSubpath()
        return path
    }
}
