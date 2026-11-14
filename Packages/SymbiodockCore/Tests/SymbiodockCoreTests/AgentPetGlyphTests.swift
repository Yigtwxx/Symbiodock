import Foundation
import Testing
@testable import SymbiodockCore

struct AgentPetGlyphTests {
    @Test func everyDrawingFillsItsGrid() {
        for tool in AgentTool.allCases {
            let art = AgentPetGlyph.art(for: tool)
            #expect(art.count == AgentPetGlyph.gridSize, "\(tool)")
            for row in art {
                #expect(row.count == AgentPetGlyph.gridSize, "\(tool)")
                let known = row.allSatisfy { "#+-.".contains($0) }
                #expect(known, "\(tool)")
            }
        }
    }

    @Test func everyToolHasAFigureOfOneLinePerColumn() {
        for tool in AgentTool.allCases {
            let glyph = AgentPetGlyph.glyph(for: tool)
            #expect(glyph.columns.count == AgentPetGlyph.columnCount, "\(tool)")
            // A figure that is mostly empty columns would not read as a figure.
            let inked = glyph.columns.filter { !$0.isEmpty }.count
            #expect(inked >= 13, "\(tool)")
        }
    }

    @Test func theLinesAndTheirGapsFillTheWidth() {
        let width = Double(AgentPetGlyph.columnCount - 1) * AgentPetGlyph.pitch + AgentPetGlyph.barWidth
        #expect(abs(width - 1) < 1e-9)
    }

    @Test func everyStretchCanBeDrawnWithRoundEnds() {
        let minimum = AgentPetGlyph.barWidth - 1e-9
        for tool in AgentTool.allCases {
            for (index, column) in AgentPetGlyph.glyph(for: tool).columns.enumerated() {
                for segment in column {
                    #expect(segment.top >= 0 && segment.bottom <= 1, "\(tool) column \(index)")
                    #expect(segment.bottom - segment.top >= minimum, "\(tool) column \(index)")
                }
                for segment in column {
                    #expect((0..<AgentPetGlyph.depthCount).contains(segment.depth), "\(tool) column \(index)")
                }
                for (upper, lower) in zip(column, column.dropFirst()) {
                    // Two stretches either touch, at different depths, or are a real break apart.
                    let gap = lower.top - upper.bottom
                    if gap == 0 {
                        #expect(upper.depth != lower.depth, "\(tool) column \(index)")
                    } else {
                        #expect(gap >= minimum, "\(tool) column \(index)")
                    }
                }
            }
        }
    }

    @Test func aDrawingBecomesLinesWithBreaks() {
        let glyph = AgentPetGlyph(art: [
            "#.+",
            "#.+",
            "..-",
            "#.#",
        ])
        /// Where the edge of the given grid row lies.
        func edge(_ row: Int) -> Double { Double(row) / Double(AgentPetGlyph.gridSize) }
        #expect(
            glyph.columns[0] == [
                .init(top: edge(0), bottom: edge(2)), .init(top: edge(3), bottom: edge(4)),
            ])
        #expect(glyph.columns[1].isEmpty)
        // A change of depth starts a new stretch without a break.
        #expect(
            glyph.columns[2] == [
                .init(top: edge(0), bottom: edge(2), depth: 1),
                .init(top: edge(2), bottom: edge(3), depth: 2),
                .init(top: edge(3), bottom: edge(4), depth: 0),
            ])
        // Whatever the drawing leaves out is empty; nothing is read outside it.
        #expect(glyph.columns.count == AgentPetGlyph.columnCount)
        let restIsEmpty = glyph.columns[3...].allSatisfy { $0.isEmpty }
        #expect(restIsEmpty)
        let nothingDrawn = AgentPetGlyph(art: []).columns.allSatisfy { $0.isEmpty }
        #expect(nothingDrawn)
    }

    @Test func everyFigureHasDepth() {
        for tool in AgentTool.allCases {
            let depths = Set(AgentPetGlyph.glyph(for: tool).columns.flatMap { $0.map(\.depth) })
            #expect(depths.contains(0), "\(tool)")
            #expect(depths.count >= 2, "\(tool)")
        }
    }

    @Test func noTwoToolsShareAFigure() {
        let glyphs = AgentTool.allCases.map(AgentPetGlyph.glyph(for:))
        for (index, glyph) in glyphs.enumerated() {
            #expect(!glyphs[(index + 1)...].contains(glyph))
        }
    }

    @Test func aWorkingPetStirsOnlyALittle() {
        for step in 0..<400 {
            let time = Double(step) * 0.037
            let values = (0..<AgentPetGlyph.columnCount).map { AgentPetMotion.sway(column: $0, at: time) }
            #expect(values.allSatisfy { abs($0) <= AgentPetMotion.swayAmplitude + 1e-9 })
        }
        // Small: less than half a grid cell.
        #expect(AgentPetMotion.swayAmplitude < 0.5 / Double(AgentPetGlyph.gridSize))
        // The lines do not move in step.
        #expect(AgentPetMotion.sway(column: 0, at: 1) != AgentPetMotion.sway(column: 3, at: 1))
    }

    @Test func aWorkingPetMovesSlowly() {
        // No line may change by more than a small part of its travel between two frames
        // at 20 frames a second: slow enough not to flicker.
        let frame = 1.0 / 20.0
        for step in 0..<400 {
            let time = Double(step) * frame
            for column in 0..<AgentPetGlyph.columnCount {
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
