import Foundation

/// A relief: how high a figure rises above the plane at each point of the unit square
/// (x to the right, y downward). 0 means there is nothing there.
typealias AgentPetRelief = @Sendable (_ x: Double, _ y: Double) -> Double

/// A pet as it is modelled: its relief, and the parts of it that give off light of their
/// own (a prompt on a screen) and are therefore brighter than anything the light falls on.
struct AgentPetModel: Sendable {
    let relief: AgentPetRelief
    var glow: AgentPetRelief?

    init(_ relief: @escaping AgentPetRelief, glow: AgentPetRelief? = nil) {
        self.relief = relief
        self.glow = glow
    }
}

/// The pieces the pets are modelled from, and the pets themselves. A pet is the figure its
/// tool is known by, shaped as a small relief so that light can fall on it.
enum AgentPetReliefs {
    // MARK: Pieces

    /// Half an ellipsoid lying on the plane.
    static func dome(
        _ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let inside = 1 - pow((x - centerX) / radiusX, 2) - pow((y - centerY) / radiusY, 2)
            return inside > 0 ? height * sqrt(inside) : 0
        }
    }

    /// A plate with round corners and a rounded shoulder `bevel` wide.
    static func slab(
        _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
        radius: Double, bevel: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let offsetX = abs(x - (left + right) / 2) - ((right - left) / 2 - radius)
            let offsetY = abs(y - (top + bottom) / 2) - ((bottom - top) / 2 - radius)
            let outside = hypot(max(offsetX, 0), max(offsetY, 0)) + min(max(offsetX, offsetY), 0) - radius
            guard outside < 0 else { return 0 }
            let across = min(-outside / bevel, 1)
            // A quarter circle: steep at the edge, flat on top.
            return height * sqrt(1 - (1 - across) * (1 - across))
        }
    }

    /// Half a tube lying between two points.
    static func tube(
        _ fromX: Double, _ fromY: Double, _ toX: Double, _ toY: Double,
        radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let alongX = toX - fromX
            let alongY = toY - fromY
            let part = min(
                max(((x - fromX) * alongX + (y - fromY) * alongY) / (alongX * alongX + alongY * alongY), 0), 1)
            let distance = hypot(x - (fromX + part * alongX), y - (fromY + part * alongY))
            return distance < radius ? height * sqrt(1 - (distance / radius) * (distance / radius)) : 0
        }
    }

    /// A four-pointed star, faceted like a cut stone.
    static func star(
        _ centerX: Double, _ centerY: Double, _ radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let reach = pow(abs(x - centerX) / radius, 0.62) + pow(abs(y - centerY) / radius, 0.62)
            return reach < 1 ? height * (1 - reach) : 0
        }
    }

    /// The near corner of a cube: three faces falling away from the centre, inside a hexagon.
    static func cubeCorner(
        _ centerX: Double, _ centerY: Double, _ radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let pointX = (x - centerX) / radius
            let pointY = (y - centerY) / radius
            let hexagon = max(
                abs(pointX) / 0.866, abs(pointX * 0.5 / 0.866 + pointY), abs(pointX * 0.5 / 0.866 - pointY))
            guard hexagon <= 1 else { return 0 }
            let fall = max(-pointY, -0.866 * pointX + 0.5 * pointY, 0.866 * pointX + 0.5 * pointY)
            return height * (1 - 0.6 * fall)
        }
    }

    /// A plain rectangle, for holes: 1 inside, 0 outside.
    static func box(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> AgentPetRelief {
        { x, y in x >= left && x <= right && y >= top && y <= bottom ? 1 : 0 }
    }

    /// Whichever piece is highest at each point.
    static func union(_ pieces: AgentPetRelief...) -> AgentPetRelief {
        { x, y in pieces.reduce(0) { max($0, $1(x, y)) } }
    }

    /// The base with nothing left wherever a hole is.
    static func cut(_ base: @escaping AgentPetRelief, _ holes: AgentPetRelief...) -> AgentPetRelief {
        { x, y in holes.contains { $0(x, y) > 0 } ? 0 : base(x, y) }
    }

    /// The base pressed down to `depth` wherever the hole is: glass, a screen.
    static func recess(
        _ base: @escaping AgentPetRelief, _ hole: @escaping AgentPetRelief, to depth: Double
    ) -> AgentPetRelief {
        { x, y in
            let height = base(x, y)
            return height > 0 && hole(x, y) > 0 ? min(height, depth) : height
        }
    }

    // MARK: Pets

    static func model(for tool: AgentTool) -> AgentPetModel {
        switch tool {
        case .claudeCode: AgentPetModel(claudeCode)
        case .codex: codex
        case .geminiCLI: AgentPetModel(geminiCLI)
        case .cursorAgent: AgentPetModel(cursorAgent)
        case .openCode: AgentPetModel(openCode)
        case .aider: AgentPetModel(aider)
        case .copilotCLI: AgentPetModel(copilotCLI)
        }
    }

    /// A plump creature: a round body ringed by eight lobes, like a burst, with two tall
    /// narrow eyes, each one line wide.
    private static var claudeCode: AgentPetRelief {
        let body = dome(0.50, 0.50, 0.31, 0.29, 0.56)
        let lobes = union(
            dome(0.50, 0.22, 0.16, 0.15, 0.42), dome(0.50, 0.78, 0.16, 0.15, 0.42),
            dome(0.19, 0.50, 0.15, 0.16, 0.40), dome(0.81, 0.50, 0.15, 0.16, 0.40),
            dome(0.28, 0.30, 0.16, 0.16, 0.42), dome(0.72, 0.30, 0.16, 0.16, 0.42),
            dome(0.28, 0.70, 0.16, 0.16, 0.42), dome(0.72, 0.70, 0.16, 0.16, 0.42))
        return cut(
            union(body, lobes),
            box(0.38, 0.39, 0.43, 0.59), box(0.57, 0.39, 0.62, 0.59))
    }

    /// A plump cloud of round lobes with a prompt glowing on its front: ">" and "_".
    private static var codex: AgentPetModel {
        let body = union(
            dome(0.50, 0.51, 0.34, 0.31, 0.56),
            dome(0.33, 0.37, 0.21, 0.20, 0.44), dome(0.63, 0.33, 0.23, 0.22, 0.48),
            dome(0.18, 0.55, 0.17, 0.17, 0.38), dome(0.82, 0.53, 0.17, 0.18, 0.40),
            dome(0.34, 0.68, 0.22, 0.19, 0.44), dome(0.67, 0.68, 0.22, 0.19, 0.44))
        let prompt = union(
            tube(0.33, 0.46, 0.45, 0.55, radius: 0.034, 1),
            tube(0.45, 0.55, 0.33, 0.64, radius: 0.034, 1),
            tube(0.53, 0.64, 0.69, 0.64, radius: 0.034, 1))
        return AgentPetModel(body, glow: prompt)
    }

    /// A four-pointed star, and a small one far behind it.
    private static var geminiCLI: AgentPetRelief {
        union(star(0.46, 0.54, 0.46, 0.55), star(0.84, 0.16, 0.15, 0.24))
    }

    /// A cube seen from a corner; the light gives each of its three faces its own tone.
    private static var cursorAgent: AgentPetRelief {
        cubeCorner(0.5, 0.5, 0.47, 0.5)
    }

    /// A terminal window with a prompt on its screen, ">" and "_", and a second window
    /// behind it.
    private static var openCode: AgentPetRelief {
        let far = slab(0.28, 0.06, 0.98, 0.66, radius: 0.06, bevel: 0.05, 0.16)
        let near = slab(0.02, 0.24, 0.76, 0.92, radius: 0.06, bevel: 0.06, 0.44)
        let screen = box(0.10, 0.40, 0.68, 0.84)
        let prompt = union(
            tube(0.18, 0.50, 0.28, 0.60, radius: 0.03, 0.4),
            tube(0.28, 0.60, 0.18, 0.70, radius: 0.03, 0.4),
            tube(0.38, 0.72, 0.54, 0.72, radius: 0.03, 0.4))
        return union(far, recess(near, screen, to: 0.10), prompt)
    }

    /// The letter A made of three tubes: the left stroke nearest, the right one farthest.
    private static var aider: AgentPetRelief {
        union(
            tube(0.54, 0.10, 0.90, 0.90, radius: 0.085, 0.20),
            tube(0.30, 0.62, 0.72, 0.62, radius: 0.07, 0.32),
            tube(0.50, 0.10, 0.12, 0.90, radius: 0.095, 0.48))
    }

    /// A round helmeted head: two goggles with sunken glass, two eyes below them, an ear
    /// on each side.
    private static var copilotCLI: AgentPetRelief {
        let head = dome(0.5, 0.50, 0.44, 0.42, 0.52)
        let ears = union(dome(0.05, 0.52, 0.07, 0.13, 0.2), dome(0.95, 0.52, 0.07, 0.13, 0.2))
        let glass = union(
            slab(0.17, 0.30, 0.45, 0.55, radius: 0.09, bevel: 0.02, 1),
            slab(0.55, 0.30, 0.83, 0.55, radius: 0.09, bevel: 0.02, 1))
        return cut(
            union(ears, recess(head, glass, to: 0.07)),
            box(0.36, 0.66, 0.41, 0.78), box(0.59, 0.66, 0.64, 0.78))
    }
}
