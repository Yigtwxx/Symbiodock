import Foundation
import Testing
@testable import SymbiodockCore

struct MarkdownBlocksTests {
    private func span(_ text: String, _ style: MarkdownInlineStyle = [], link: String? = nil)
        -> MarkdownSpan
    {
        MarkdownSpan(text, style, link: link.flatMap(URL.init(string:)))
    }

    @Test func headingsKeepTheirLevelAndText() {
        let blocks = MarkdownBlocks.parse("# One\n\n## Two\n\n###### Six\n\nSetext\n===\n")
        #expect(blocks.map(\.kind) == [
            .heading(level: 1), .heading(level: 2), .heading(level: 6), .heading(level: 1),
        ])
        #expect(blocks.map { $0.spans.map(\.text).joined() } == ["One", "Two", "Six", "Setext"])
        #expect(blocks.allSatisfy { $0.listDepth == 0 && $0.quoteDepth == 0 && $0.marker == nil })
    }

    @Test func paragraphsAreSeparateBlocksAndSoftBreaksBecomeSpaces() {
        let blocks = MarkdownBlocks.parse("First line\nsame paragraph\n\nSecond")
        #expect(blocks == [
            MarkdownBlock(.paragraph, spans: [span("First line same paragraph")]),
            MarkdownBlock(.paragraph, spans: [span("Second")]),
        ])
    }

    @Test func hardBreaksStayInsideTheParagraph() {
        let blocks = MarkdownBlocks.parse("One  \ntwo\\\nthree")
        #expect(blocks == [MarkdownBlock(.paragraph, spans: [span("One\ntwo\nthree")])])
    }

    @Test func inlineStylesAndLinksBecomeSpans() {
        let blocks = MarkdownBlocks.parse(
            "Has **bold**, *it*, ***both***, ~~gone~~, `code` and [a link](https://example.com).")
        #expect(blocks.count == 1)
        #expect(blocks[0].spans == [
            span("Has "), span("bold", .bold), span(", "), span("it", .italic), span(", "),
            span("both", [.bold, .italic]), span(", "), span("gone", .strikethrough), span(", "),
            span("code", .code), span(" and "), span("a link", link: "https://example.com"),
            span("."),
        ])
    }

    @Test func imagesBecomeTheirAltText() {
        let blocks = MarkdownBlocks.parse("![A screenshot](shot.png) after")
        #expect(blocks == [MarkdownBlock(.paragraph, spans: [span("A screenshot after")])])
    }

    @Test func inlineHTMLTagsAreDroppedAndBrBreaksTheLine() {
        let blocks = MarkdownBlocks.parse("<b>bold</b> one<br>two")
        #expect(blocks == [MarkdownBlock(.paragraph, spans: [span("bold one\ntwo")])])
    }

    @Test func nestedListsCarryDepthAndMarkers() {
        let blocks = MarkdownBlocks.parse(
            """
            - one
            - two
              - inner a
              - inner b
            - three

            3. third
            4. fourth
            """)
        #expect(blocks.map { $0.spans.map(\.text).joined() } == [
            "one", "two", "inner a", "inner b", "three", "third", "fourth",
        ])
        #expect(blocks.map(\.listDepth) == [1, 1, 2, 2, 1, 1, 1])
        #expect(blocks.map(\.marker) == ["•", "•", "•", "•", "•", "3.", "4."])
        #expect(blocks.map(\.startsList) == [true, false, true, false, false, true, false])
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
    }

    @Test func aListItemsSecondParagraphHasNoMarker() {
        let blocks = MarkdownBlocks.parse("- first\n\n  more of it\n- next")
        #expect(blocks.map(\.marker) == ["•", nil, "•"])
        #expect(blocks.map(\.listDepth) == [1, 1, 1])
    }

    @Test func codeBlocksKeepLinesAndLanguageWithoutTheLastNewline() {
        let blocks = MarkdownBlocks.parse("```swift\nlet a = 1\n    indented\n```\n\n```\nplain\n```")
        #expect(blocks == [
            MarkdownBlock(.code(language: "swift"), spans: [span("let a = 1\n    indented")]),
            MarkdownBlock(.code(language: nil), spans: [span("plain")]),
        ])
    }

    @Test func blockQuotesCountTheirDepthAndHoldLists() {
        let blocks = MarkdownBlocks.parse("> quoted\n>\n> > deeper\n\n> 1. in a quote\n")
        #expect(blocks.map { $0.spans.map(\.text).joined() } == ["quoted", "deeper", "in a quote"])
        #expect(blocks.map(\.quoteDepth) == [1, 2, 1])
        #expect(blocks.map(\.listDepth) == [0, 0, 1])
        #expect(blocks[2].marker == "1.")
    }

    @Test func thematicBreaksAreTheirOwnBlock() {
        let blocks = MarkdownBlocks.parse("above\n\n---\n\nbelow")
        #expect(blocks.map(\.kind) == [.paragraph, .thematicBreak, .paragraph])
        #expect(blocks[1].spans.isEmpty)
    }

    @Test func tablesGroupCellsIntoRowsUnderTheHeader() {
        let blocks = MarkdownBlocks.parse(
            """
            | Name | Size |
            |:-----|-----:|
            | **A** | 1 |
            | B | 22 |
            """)
        #expect(blocks.count == 1)
        guard case .table(let table) = blocks.first?.kind else {
            Issue.record("not a table: \(blocks)")
            return
        }
        #expect(table.alignments == [.left, .right])
        #expect(table.header == [[span("Name")], [span("Size")]])
        #expect(table.rows == [
            [[span("A", .bold)], [span("1")]],
            [[span("B")], [span("22")]],
        ])
    }

    @Test func turkishLettersSurvive() {
        let blocks = MarkdownBlocks.parse("## ğüşıöç ĞÜŞİÖÇ")
        #expect(blocks == [MarkdownBlock(.heading(level: 2), spans: [span("ğüşıöç ĞÜŞİÖÇ")])])
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(MarkdownBlocks.parse("").isEmpty)
        #expect(MarkdownBlocks.parse("\n\n  \n").isEmpty)
    }

    // MARK: Plain text

    @Test func plainTextDropsTheMarkers() {
        let text = MarkdownBlocks.plainText(
            MarkdownBlocks.parse(
                """
                # Title

                Some **bold** and [a link](https://example.com) and <https://auto.example>.

                - one
                  - inner
                - two

                1. first
                2. second

                > quoted

                ```
                code line
                  kept
                ```

                ---

                | A | B |
                |---|---|
                | 1 | 2 |
                """))
        #expect(
            text == """
                Title

                Some bold and a link (https://example.com) and https://auto.example.

                •  one
                   •  inner
                •  two

                1. first
                2. second

                    quoted

                    code line
                      kept

                ────────────────────

                A\tB
                1\t2

                """)
    }

    @Test func plainTextIndentsEveryLineOfABrokenListItem() {
        let text = MarkdownBlocks.plainText(MarkdownBlocks.parse("- one  \n  two"))
        #expect(text == "•  one\n   two\n")
    }
}
