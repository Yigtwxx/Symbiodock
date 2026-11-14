import Foundation

/// A tool's pet as the island draws it: a field of fine vertical lines, where the figure
/// shows as the lines' brightness changing along their length. The figure is a small
/// relief lit from the upper left, so its forms read as volume: what faces the light is
/// bright, what turns away or stands back is dim. All measures are fractions of the
/// figure's side.
public struct AgentPetFigure: Equatable, Sendable {
    /// A stretch of one line where the figure is, with the brightness along it.
    public struct Stretch: Equatable, Sendable {
        /// 0 is the top of the figure, 1 its bottom.
        public let top: Double
        public let bottom: Double
        /// Brightness from `top` to `bottom`, evenly spaced, each above 0. Up to 1 it is
        /// how much of the tool's colour shows; above 1 the part glows, towards white.
        public let shades: [Double]
    }

    public static let lineCount = 21
    /// How finely the brightness along a line is recorded.
    public static let samplesPerLine = 4 * lineCount
    /// From one line's leading edge to the next: the lines and their gaps fill the width.
    public static let pitch = 1.0 / (Double(lineCount - 1) + barShare)
    /// A line is a little wider than the gap beside it, so the colour stays strong.
    public static let barWidth = barShare * pitch
    private static let barShare = 0.6
    /// How bright the lines are where there is no figure: the ground it stands out from.
    public static let groundStrength = 0.085
    /// The dimmest a part of a figure can be, so that it always stands out from the ground.
    public static let faintestShade = 0.36
    /// The brightness of a part that gives off light of its own: most of the way to white.
    public static let glowShade = 1.8

    /// Brightness along each line, left to right and top to bottom; 0 where the line shows
    /// only the ground, `glowShade` where the figure glows.
    public let lines: [[Double]]

    init(lines: [[Double]]) {
        self.lines = lines
    }

    /// The figure of a tool. Each is worked out once and kept.
    public static func figure(for tool: AgentTool) -> AgentPetFigure {
        figures[tool] ?? AgentPetFigure(model: AgentPetReliefs.model(for: tool))
    }

    private static let figures: [AgentTool: AgentPetFigure] = Dictionary(
        uniqueKeysWithValues: AgentTool.allCases.map {
            ($0, AgentPetFigure(model: AgentPetReliefs.model(for: $0)))
        })

    /// The stretches of one line where the figure is, top to bottom.
    public func stretches(ofLine index: Int) -> [Stretch] {
        guard lines.indices.contains(index) else { return [] }
        let line = lines[index]
        guard !line.isEmpty else { return [] }
        let count = Double(line.count)
        var stretches: [Stretch] = []
        var start: Int?
        for row in 0...line.count {
            let inked = row < line.count && line[row] > 0
            if inked, start == nil { start = row }
            guard !inked, let from = start else { continue }
            start = nil
            stretches.append(
                Stretch(top: Double(from) / count, bottom: Double(row) / count, shades: Array(line[from..<row])))
        }
        return stretches
    }
}

// MARK: Lighting

extension AgentPetFigure {
    /// Where the light comes from: upper left, towards the viewer.
    private static let light = (x: -0.52, y: -0.62, z: 0.59)
    /// A relief's outline is a cliff; a cliff this steep or steeper is lit as this steep.
    private static let steepestSlope = 2.2
    private static let step = 0.006

    /// Lights a relief and records what each line sees of it.
    init(relief: @escaping AgentPetRelief) {
        self.init(model: AgentPetModel(relief))
    }

    /// Lights a model and records what each line sees of it. Where the model glows, on
    /// the figure, the line is at `glowShade` whatever the light does.
    init(model: AgentPetModel) {
        let peak = Self.peak(of: model.relief)
        lines = (0..<Self.lineCount).map { column in
            let x = Double(column) * Self.pitch + Self.barWidth / 2
            return (0..<Self.samplesPerLine).map { row in
                let y = (Double(row) + 0.5) / Double(Self.samplesPerLine)
                let shade = Self.shade(of: model.relief, x: x, y: y, peak: peak)
                guard shade > 0, let glow = model.glow, glow(x, y) > 0 else { return shade }
                return Self.glowShade
            }
        }
    }

    /// The highest point of a relief.
    private static func peak(of relief: AgentPetRelief) -> Double {
        var highest = 0.0
        for column in 0..<60 {
            for row in 0..<60 {
                highest = max(highest, relief((Double(column) + 0.5) / 60, (Double(row) + 0.5) / 60))
            }
        }
        return max(highest, 0.001)
    }

    /// How bright the relief is at a point: 0 where there is nothing.
    private static func shade(of relief: AgentPetRelief, x: Double, y: Double, peak: Double) -> Double {
        let height = relief(x, y)
        guard height > 0, height.isFinite else { return 0 }
        let slopeX = clamp((relief(x + step, y) - relief(x - step, y)) / (2 * step))
        let slopeY = clamp((relief(x, y + step) - relief(x, y - step)) / (2 * step))
        let length = sqrt(slopeX * slopeX + slopeY * slopeY + 1)
        let facing = max(0, (-slopeX * light.x - slopeY * light.y + light.z) / length)
        // What stands farther back is dimmer. The shading is kept gentle: the figure should
        // read as a form, and still show its tool's colour at full strength where lit.
        let nearness = 0.68 + 0.32 * min(height / peak, 1)
        return min(max(pow((0.52 + 0.48 * facing) * nearness, 0.62), faintestShade), 1)
    }

    private static func clamp(_ slope: Double) -> Double {
        slope.isFinite ? min(max(slope, -steepestSlope), steepestSlope) : 0
    }
}

/// How a pet moves. Pure functions of time, so the views only draw.
public enum AgentPetMotion {
    /// How much larger a line is drawn at the crest of the wave, about its own centre: a
    /// touch thicker and longer, as if it came towards the viewer.
    public static let waveGrowth = 0.10
    /// How strongly a line shows while it waits for the crest; at the crest it shows in
    /// full. What is nearer is brighter, in the pet's own colours: nothing white is added.
    public static let waveRest = 0.82
    /// Seconds from the start of one crest to the start of the next.
    public static let wavePeriod: TimeInterval = 2.4
    /// Seconds a crest takes to cross the pet, from entering at the left to leaving at the
    /// right; the pet rests for the remainder of the period.
    public static let waveTravel: TimeInterval = 1.3
    /// How many lines wide a crest is: the width of the raised cosine.
    public static let waveWidth = 5.0

    /// How far forward line `column` (0 is the leftmost of `AgentPetFigure.lineCount`) is at
    /// `time`: 0 at rest, 1 at the crest. The wave travels in depth, not up and down. One
    /// crest runs from the left edge to the right edge, each line coming forward and going
    /// back smoothly as it passes; then the pet rests until the next crest.
    public static func wave(column: Int, at time: TimeInterval) -> Double {
        var beat = time.truncatingRemainder(dividingBy: wavePeriod)
        if beat < 0 { beat += wavePeriod }
        guard beat < waveTravel else { return 0 }
        // The crest enters half its width before the first line and leaves half its width
        // after the last, so every line is at rest when the crest starts and ends.
        let reach = Double(AgentPetFigure.lineCount - 1) + waveWidth
        let crest = -waveWidth / 2 + reach * beat / waveTravel
        let distance = abs(Double(column) - crest)
        guard distance < waveWidth / 2 else { return 0 }
        return 0.5 * (1 + cos(2 * .pi * distance / waveWidth))
    }
}
