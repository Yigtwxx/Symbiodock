import Foundation
import Testing
@testable import SymbiodockCore

struct AgentPetFigureTests {
    /// Every shade of a figure that is not empty.
    private func ink(_ figure: AgentPetFigure) -> [Double] {
        figure.lines.flatMap { $0 }.filter { $0 > 0 }
    }

    @Test func everyToolHasAFigureOnEveryLine() {
        for tool in AgentTool.allCases {
            let figure = AgentPetFigure.figure(for: tool)
            #expect(figure.lines.count == AgentPetFigure.lineCount, "\(tool)")
            for line in figure.lines {
                #expect(line.count == AgentPetFigure.samplesPerLine, "\(tool)")
            }
        }
    }

    @Test func theLinesAndTheirGapsFillTheWidth() {
        let width = Double(AgentPetFigure.lineCount - 1) * AgentPetFigure.pitch + AgentPetFigure.barWidth
        #expect(abs(width - 1) < 1e-9)
    }

    @Test func aFigureAlwaysStandsOutFromTheGround() {
        #expect(AgentPetFigure.groundStrength < AgentPetFigure.faintestShade)
        for tool in AgentTool.allCases {
            let shades = ink(AgentPetFigure.figure(for: tool))
            let inRange = shades.allSatisfy {
                ($0 >= AgentPetFigure.faintestShade && $0 <= 1) || $0 == AgentPetFigure.glowShade
            }
            #expect(inRange, "\(tool)")
        }
    }

    @Test func aFigureFillsAFairPartOfItsSquare() {
        let all = Double(AgentPetFigure.lineCount * AgentPetFigure.samplesPerLine)
        for tool in AgentTool.allCases {
            let share = Double(ink(AgentPetFigure.figure(for: tool)).count) / all
            #expect(share > 0.1 && share < 0.8, "\(tool): \(share)")
        }
    }

    @Test func everyFigureHasLightAndShade() {
        for tool in AgentTool.allCases {
            // What the light does, leaving aside the parts that glow by themselves.
            let shades = ink(AgentPetFigure.figure(for: tool)).filter { $0 <= 1 }
            let range = (shades.max() ?? 0) - (shades.min() ?? 0)
            #expect(range >= 0.3, "\(tool): \(range)")
            #expect((shades.max() ?? 0) >= 0.9, "\(tool)")
        }
    }

    @Test func noTwoToolsShareAFigure() {
        let figures = AgentTool.allCases.map(AgentPetFigure.figure(for:))
        for (index, figure) in figures.enumerated() {
            #expect(!figures[(index + 1)...].contains(figure))
        }
    }

    @Test func aFigureIsTheSameEveryTime() {
        #expect(AgentPetFigure.figure(for: .codex) == AgentPetFigure.figure(for: .codex))
        #expect(
            AgentPetFigure.figure(for: .aider)
                == AgentPetFigure(model: AgentPetReliefs.model(for: .aider)))
    }

    @Test func aGlowingPartIsBrighterThanAnythingLit() {
        #expect(AgentPetFigure.glowShade > 1)
        // The prompt on the Codex cloud glows; a few lines carry it, not the whole figure.
        let codex = ink(AgentPetFigure.figure(for: .codex))
        let glowing = codex.filter { $0 == AgentPetFigure.glowShade }.count
        #expect(glowing > 0)
        #expect(Double(glowing) < 0.2 * Double(codex.count))
        // Glow shows only on the figure, never on the ground beside it.
        let model = AgentPetModel({ x, _ in x < 0.5 ? 0.3 : 0 }, glow: { _, _ in 1 })
        let figure = AgentPetFigure(model: model)
        let left = figure.lines[0].allSatisfy { $0 == AgentPetFigure.glowShade }
        let right = figure.lines[AgentPetFigure.lineCount - 1].allSatisfy { $0 == 0 }
        #expect(left)
        #expect(right)
    }

    @Test func aLineIsCutIntoItsStretches() {
        let figure = AgentPetFigure(lines: [[0, 0.5, 0.6, 0, 0.3], [0, 0, 0, 0, 0], []])
        #expect(
            figure.stretches(ofLine: 0) == [
                .init(top: 0.2, bottom: 0.6, shades: [0.5, 0.6]),
                .init(top: 0.8, bottom: 1, shades: [0.3]),
            ])
        #expect(figure.stretches(ofLine: 1).isEmpty)
        #expect(figure.stretches(ofLine: 2).isEmpty)
        #expect(figure.stretches(ofLine: 3).isEmpty)
        #expect(figure.stretches(ofLine: -1).isEmpty)
    }

    @Test func theStretchesOfAFigureCoverItsInk() {
        for tool in AgentTool.allCases {
            let figure = AgentPetFigure.figure(for: tool)
            var covered = 0
            for index in figure.lines.indices {
                for stretch in figure.stretches(ofLine: index) {
                    #expect(stretch.top >= 0 && stretch.bottom <= 1 && stretch.top < stretch.bottom, "\(tool)")
                    #expect(!stretch.shades.isEmpty, "\(tool)")
                    covered += stretch.shades.count
                }
            }
            #expect(covered == ink(figure).count, "\(tool)")
        }
    }

    @Test func aReliefThatMisbehavesGivesNoInk() {
        let figure = AgentPetFigure(relief: { x, _ in x < 0.5 ? .nan : .infinity })
        let empty = figure.lines.allSatisfy { line in line.allSatisfy { $0 == 0 } }
        #expect(empty)
    }

    private static let frame = 1.0 / 60.0
    private static let columns = 0..<AgentPetFigure.lineCount

    /// The moment in one period at which a line is forward the most, found by sampling.
    private func peak(ofColumn column: Int) -> (time: TimeInterval, lift: Double, count: Int) {
        let steps = 2400
        let values = (0..<steps).map {
            AgentPetMotion.wave(column: column, at: Double($0) * AgentPetMotion.wavePeriod / Double(steps))
        }
        let top = values.max() ?? 0
        let first = values.firstIndex(of: top) ?? 0
        // Count separate rises above 90 % of the height.
        var rises = 0
        for index in values.indices where values[index] > 0.9 {
            if index == 0 || values[index - 1] <= 0.9 { rises += 1 }
        }
        return (Double(first) * AgentPetMotion.wavePeriod / Double(steps), top, rises)
    }

    @Test func aLineIsNeverMoreThanFullyForward() {
        for step in 0..<1000 {
            let time = Double(step) * 0.0071
            for column in Self.columns {
                let lift = AgentPetMotion.wave(column: column, at: time)
                #expect(lift >= 0 && lift <= 1 + 1e-12)
            }
        }
        #expect(AgentPetMotion.waveGrowth > 0 && AgentPetMotion.waveGrowth <= 0.15)
        #expect(AgentPetMotion.waveRest >= 0.6 && AgentPetMotion.waveRest < 1)
    }

    @Test func everyLineRisesToTheFullHeightOncePerPeriod() {
        for column in Self.columns {
            let result = peak(ofColumn: column)
            #expect(abs(result.lift - 1) < 0.01, "\(column)")
            #expect(result.count == 1, "\(column)")
        }
    }

    @Test func theCrestTravelsFromLeftToRight() {
        let left = peak(ofColumn: 0).time
        let middle = peak(ofColumn: AgentPetFigure.lineCount / 2).time
        let right = peak(ofColumn: AgentPetFigure.lineCount - 1).time
        #expect(left < middle)
        #expect(middle < right)
        #expect(right <= AgentPetMotion.waveTravel)
    }

    @Test func thePetRestsOnceTheCrestHasLeft() {
        var time = AgentPetMotion.waveTravel
        while time < AgentPetMotion.wavePeriod {
            for column in Self.columns {
                #expect(AgentPetMotion.wave(column: column, at: time) == 0)
            }
            time += 0.01
        }
        // And the pet starts the period at rest, too.
        for column in Self.columns {
            #expect(AgentPetMotion.wave(column: column, at: 0) < 1e-9)
        }
    }

    @Test func theLiftChangesSmoothly() {
        // Between two frames at 60 a second no line may change by more than a quarter of its
        // travel.
        for step in 0..<1500 {
            let time = Double(step) * 0.0013 - 1
            for column in Self.columns {
                let change = abs(
                    AgentPetMotion.wave(column: column, at: time + Self.frame)
                        - AgentPetMotion.wave(column: column, at: time))
                #expect(change <= 0.25)
            }
        }
    }

    @Test func theWaveRepeatsEveryPeriodAndAlsoBeforeTheReferenceDate() {
        for step in 0..<200 {
            let time = Double(step) * 0.017
            for column in Self.columns {
                let now = AgentPetMotion.wave(column: column, at: time)
                #expect(abs(AgentPetMotion.wave(column: column, at: time + AgentPetMotion.wavePeriod) - now) < 1e-9)
                #expect(abs(AgentPetMotion.wave(column: column, at: time - 5 * AgentPetMotion.wavePeriod) - now) < 1e-9)
            }
        }
        #expect(AgentPetMotion.wave(column: 10, at: -AgentPetMotion.wavePeriod + 0.65) > 0)
    }
}
