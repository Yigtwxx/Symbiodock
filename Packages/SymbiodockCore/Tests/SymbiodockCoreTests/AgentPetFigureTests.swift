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
            let inRange = shades.allSatisfy { $0 >= AgentPetFigure.faintestShade && $0 <= 1 && $0.isFinite }
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
            let shades = ink(AgentPetFigure.figure(for: tool))
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
                == AgentPetFigure(relief: AgentPetReliefs.relief(for: .aider)))
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

    @Test func aWorkingPetStirsOnlyALittle() {
        for step in 0..<400 {
            let time = Double(step) * 0.037
            let values = (0..<AgentPetFigure.lineCount).map { AgentPetMotion.sway(column: $0, at: time) }
            let small = values.allSatisfy { abs($0) <= AgentPetMotion.swayAmplitude + 1e-9 }
            #expect(small)
        }
        #expect(AgentPetMotion.swayAmplitude <= 0.03)
        // The lines do not move in step.
        #expect(AgentPetMotion.sway(column: 0, at: 1) != AgentPetMotion.sway(column: 3, at: 1))
    }

    @Test func aWorkingPetMovesSlowly() {
        // No line may change by more than a small part of its travel between two frames
        // at 20 frames a second: slow enough not to flicker.
        let frame = 1.0 / 20.0
        for step in 0..<400 {
            let time = Double(step) * frame
            for column in 0..<AgentPetFigure.lineCount {
                let change = abs(
                    AgentPetMotion.sway(column: column, at: time + frame)
                        - AgentPetMotion.sway(column: column, at: time))
                #expect(change <= AgentPetMotion.swayAmplitude * 0.2)
            }
        }
    }

    @Test func thePetHopsTwiceAndThenRests() {
        let length = AgentPetMotion.hopLength
        #expect(AgentPetMotion.hop(at: 0) == 0)
        #expect(abs(AgentPetMotion.hop(at: length / 2) - AgentPetMotion.hopHeight) < 1e-9)
        #expect(abs(AgentPetMotion.hop(at: length * 1.5) - AgentPetMotion.hopHeight) < 1e-9)
        #expect(AgentPetMotion.hop(at: length * 2.5) == 0)
        #expect(AgentPetMotion.hop(at: AgentPetMotion.hopPeriod - 0.01) == 0)
        // The next beat hops again, and time before the reference date is no exception.
        #expect(AgentPetMotion.hop(at: AgentPetMotion.hopPeriod + length / 2) > 0)
        #expect(AgentPetMotion.hop(at: -AgentPetMotion.hopPeriod + length / 2) > 0)
        for step in 0..<300 {
            let value = AgentPetMotion.hop(at: Double(step) * 0.017)
            #expect(value >= 0 && value <= AgentPetMotion.hopHeight + 1e-9)
        }
    }
}
