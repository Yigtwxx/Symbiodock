import Foundation
import Testing
@testable import SymbiodockCore

struct AgentPetGlyphTests {
    @Test func everyToolHasAFigureOfSevenColumns() {
        for tool in AgentTool.allCases {
            let glyph = AgentPetGlyph.glyph(for: tool)
            #expect(glyph.columns.count == AgentPetGlyph.columnCount, "\(tool)")
            #expect(glyph.columns.allSatisfy { !$0.isEmpty }, "\(tool)")
        }
    }

    @Test func sevenBarsAndSixGapsFillTheWidth() {
        let width = Double(AgentPetGlyph.columnCount - 1) * AgentPetGlyph.pitch + AgentPetGlyph.barWidth
        #expect(abs(width - 1) < 1e-9)
    }

    @Test func everyStretchCanBeDrawnAsACapsule() {
        let minimum = AgentPetGlyph.barWidth - 1e-9
        for tool in AgentTool.allCases {
            for (index, column) in AgentPetGlyph.glyph(for: tool).columns.enumerated() {
                for segment in column {
                    #expect(segment.top >= 0 && segment.bottom <= 1, "\(tool) column \(index)")
                    #expect(segment.bottom - segment.top >= minimum, "\(tool) column \(index)")
                }
                for (upper, lower) in zip(column, column.dropFirst()) {
                    #expect(lower.top - upper.bottom >= minimum, "\(tool) column \(index)")
                }
            }
        }
    }

    @Test func noTwoToolsShareAFigure() {
        let glyphs = AgentTool.allCases.map(AgentPetGlyph.glyph(for:))
        for (index, glyph) in glyphs.enumerated() {
            #expect(!glyphs[(index + 1)...].contains(glyph))
        }
    }

    @Test func theWaveStaysSmallAndDiffersBetweenColumns() {
        for step in 0..<200 {
            let time = Double(step) * 0.037
            let values = (0..<AgentPetGlyph.columnCount).map { AgentPetMotion.sway(column: $0, at: time) }
            #expect(values.allSatisfy { abs($0) <= AgentPetMotion.swayAmplitude + 1e-9 })
        }
        #expect(AgentPetMotion.sway(column: 0, at: 1) != AgentPetMotion.sway(column: 3, at: 1))
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
