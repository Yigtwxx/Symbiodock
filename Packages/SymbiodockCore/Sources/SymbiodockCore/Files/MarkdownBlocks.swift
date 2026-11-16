import Foundation

/// How a stretch of text inside a block is set.
public struct MarkdownInlineStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = MarkdownInlineStyle(rawValue: 1 << 0)
    public static let italic = MarkdownInlineStyle(rawValue: 1 << 1)
    public static let strikethrough = MarkdownInlineStyle(rawValue: 1 << 2)
    public static let code = MarkdownInlineStyle(rawValue: 1 << 3)
}

/// A run of text with one style and at most one link. A hard line break inside a block is
/// a "\n" in `text`.
public struct MarkdownSpan: Equatable, Sendable {
    public var text: String
    public var style: MarkdownInlineStyle
    public var link: URL?

    public init(_ text: String, _ style: MarkdownInlineStyle = [], link: URL? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}

public enum MarkdownColumnAlignment: Equatable, Sendable {
    case left, center, right
}

/// A table: one row of header cells and the body rows, each cell a list of spans.
public struct MarkdownTable: Equatable, Sendable {
    public var alignments: [MarkdownColumnAlignment]
    public var header: [[MarkdownSpan]]
    public var rows: [[[MarkdownSpan]]]

    public init(
        alignments: [MarkdownColumnAlignment], header: [[MarkdownSpan]], rows: [[[MarkdownSpan]]]
    ) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

public enum MarkdownBlockKind: Equatable, Sendable {
    case heading(level: Int)
    case paragraph
    case code(language: String?)
    case thematicBreak
    case table(MarkdownTable)
}

/// One block of the document in reading order: a heading, a paragraph (also one inside a list
/// item or a quote), a code block, a rule or a table.
public struct MarkdownBlock: Equatable, Sendable {
    public var kind: MarkdownBlockKind
    /// Empty for rules and tables (a table keeps its cells in its kind).
    public var spans: [MarkdownSpan]
    /// How many lists the block sits in; 0 outside lists.
    public var listDepth: Int
    /// How many block quotes the block sits in.
    public var quoteDepth: Int
    /// "•" or "3." on the first block of a list item; nil otherwise.
    public var marker: String?
    /// The first block of its innermost list: a new list, not the next item.
    public var startsList: Bool

    public init(
        _ kind: MarkdownBlockKind, spans: [MarkdownSpan] = [], listDepth: Int = 0,
        quoteDepth: Int = 0, marker: String? = nil, startsList: Bool = false
    ) {
        self.kind = kind
        self.spans = spans
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
        self.marker = marker
        self.startsList = startsList
    }
}

/// Markdown read with the system's own parser (`AttributedString(markdown:)`) and walked into
/// blocks, because AppKit does not lay out the parser's block structure by itself.
public enum MarkdownBlocks {
    /// Never fails: what the parser cannot read comes back as plain paragraphs.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return plainParagraphs(source)
        }
        return walk(parsed)
    }

    /// Paragraphs split at blank lines, for text the parser refuses.
    private static func plainParagraphs(_ source: String) -> [MarkdownBlock] {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { MarkdownBlock(.paragraph, spans: [MarkdownSpan($0)]) }
    }

    private struct TableBuilder {
        var identity: Int
        var alignments: [MarkdownColumnAlignment]
        var header: [[MarkdownSpan]] = []
        var rows: [[[MarkdownSpan]]] = []
        var row: Int?
        var rowIsHeader = false
        var cell: Int?
    }

    private static func walk(_ parsed: AttributedString) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var current: Int?  // identity of the leaf block the last run belonged to
        var table: TableBuilder?
        var seenItems: Set<Int> = []
        var seenLists: Set<Int> = []

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let text = String(parsed[run.range].characters)
            guard let span = span(text, run: run) else { continue }

            // Tables: cells gather into rows; the table becomes one block.
            if let tableIndex = components.firstIndex(where: {
                if case .table = $0.kind { return true } else { return false }
            }) {
                let tableComponent = components[tableIndex]
                if table?.identity != tableComponent.identity {
                    flush(&table, into: &blocks)
                    guard case .table(let columns) = tableComponent.kind else { continue }
                    table = TableBuilder(
                        identity: tableComponent.identity,
                        alignments: columns.map(alignment))
                    blocks.append(
                        context(.table(MarkdownTable(alignments: [], header: [], rows: [])),
                                components: Array(components[tableIndex...]),
                                seenItems: &seenItems, seenLists: &seenLists))
                }
                add(span, components: components, to: &table)
                current = tableComponent.identity
                continue
            }
            flush(&table, into: &blocks)

            let leaf = components.first
            let identity = leaf?.identity ?? -1
            if identity == current, !blocks.isEmpty {
                append(span, to: &blocks[blocks.count - 1])
                continue
            }
            current = identity
            let kind: MarkdownBlockKind
            switch leaf?.kind {
            case .header(let level): kind = .heading(level: min(max(level, 1), 6))
            case .codeBlock(let language):
                kind = .code(language: language.flatMap { $0.isEmpty ? nil : $0 })
            case .thematicBreak: kind = .thematicBreak
            default: kind = .paragraph
            }
            var block = context(kind, components: components, seenItems: &seenItems,
                                seenLists: &seenLists)
            if kind != .thematicBreak { append(span, to: &block) }
            blocks.append(block)
        }
        flush(&table, into: &blocks)

        // Code keeps its lines but not the newline that closes the fence.
        for index in blocks.indices {
            guard case .code = blocks[index].kind, var last = blocks[index].spans.last else {
                continue
            }
            while last.text.hasSuffix("\n") { last.text.removeLast() }
            blocks[index].spans[blocks[index].spans.count - 1] = last
        }
        return blocks.filter { block in
            switch block.kind {
            case .thematicBreak, .table, .code: return true
            default:
                return !block.spans.allSatisfy {
                    $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }

    /// A block with its place among lists and quotes; the first block of a list item takes
    /// the item's marker.
    private static func context(
        _ kind: MarkdownBlockKind, components: [PresentationIntent.IntentType],
        seenItems: inout Set<Int>, seenLists: inout Set<Int>
    ) -> MarkdownBlock {
        var block = MarkdownBlock(kind)
        var ordered: Bool?
        var item: PresentationIntent.IntentType?
        for component in components {
            switch component.kind {
            case .orderedList, .unorderedList:
                block.listDepth += 1
                if ordered == nil, item != nil {
                    if case .orderedList = component.kind { ordered = true } else { ordered = false }
                    if seenLists.insert(component.identity).inserted { block.startsList = true }
                }
            case .listItem:
                if item == nil { item = component }
            case .blockQuote:
                block.quoteDepth += 1
            default:
                break
            }
        }
        if let item, case .listItem(let ordinal) = item.kind,
            seenItems.insert(item.identity).inserted
        {
            block.marker = ordered == true ? "\(ordinal)." : "•"
        }
        return block
    }

    /// The span a run makes, or nil for a run that adds nothing (an HTML tag).
    private static func span(_ text: String, run: AttributedString.Runs.Run) -> MarkdownSpan? {
        let intent = run.inlinePresentationIntent ?? []
        var text = text
        if intent.contains(.inlineHTML) {
            let tag = text.lowercased().replacingOccurrences(of: " ", with: "")
            guard tag.hasPrefix("<br") else { return nil }
            text = "\n"
        } else if intent.contains(.softBreak) {
            text = " "
        } else if intent.contains(.lineBreak) {
            text = "\n"
        }
        var style: MarkdownInlineStyle = []
        if intent.contains(.stronglyEmphasized) { style.insert(.bold) }
        if intent.contains(.emphasized) { style.insert(.italic) }
        if intent.contains(.strikethrough) { style.insert(.strikethrough) }
        if intent.contains(.code) { style.insert(.code) }
        // An image is its alt text; nothing is loaded.
        let link = run.imageURL == nil ? run.link : nil
        return MarkdownSpan(text, style, link: link)
    }

    private static func append(_ span: MarkdownSpan, to block: inout MarkdownBlock) {
        merge(span, into: &block.spans)
    }

    private static func merge(_ span: MarkdownSpan, into spans: inout [MarkdownSpan]) {
        guard !span.text.isEmpty else { return }
        if let last = spans.last, last.style == span.style, last.link == span.link {
            spans[spans.count - 1].text += span.text
        } else {
            spans.append(span)
        }
    }

    private static func alignment(_ column: PresentationIntent.TableColumn)
        -> MarkdownColumnAlignment
    {
        switch column.alignment {
        case .center: .center
        case .right: .right
        default: .left
        }
    }

    private static func add(
        _ span: MarkdownSpan, components: [PresentationIntent.IntentType],
        to table: inout TableBuilder?
    ) {
        guard var builder = table else { return }
        var cellIndex: Int?
        var rowIdentity: Int?
        var isHeader = false
        for component in components {
            switch component.kind {
            case .tableCell(let column): cellIndex = column
            case .tableHeaderRow:
                rowIdentity = component.identity
                isHeader = true
            case .tableRow: rowIdentity = component.identity
            default: break
            }
        }
        guard let cellIndex, let rowIdentity else { return }
        if builder.row != rowIdentity {
            builder.row = rowIdentity
            builder.rowIsHeader = isHeader
            if !isHeader { builder.rows.append([]) }
        }
        func put(_ cells: inout [[MarkdownSpan]]) {
            while cells.count <= cellIndex { cells.append([]) }
            merge(span, into: &cells[cellIndex])
        }
        if builder.rowIsHeader {
            put(&builder.header)
        } else {
            put(&builder.rows[builder.rows.count - 1])
        }
        table = builder
    }

    /// Writes the finished table into the placeholder block appended when it began.
    private static func flush(_ table: inout TableBuilder?, into blocks: inout [MarkdownBlock]) {
        guard let builder = table else { return }
        table = nil
        guard let index = blocks.lastIndex(where: {
            if case .table = $0.kind { return true } else { return false }
        }) else { return }
        let columns = max(
            builder.alignments.count, builder.header.count,
            builder.rows.map(\.count).max() ?? 0)
        func padded(_ cells: [[MarkdownSpan]]) -> [[MarkdownSpan]] {
            cells + Array(repeating: [], count: max(0, columns - cells.count))
        }
        blocks[index].kind = .table(
            MarkdownTable(
                alignments: builder.alignments
                    + Array(repeating: .left, count: max(0, columns - builder.alignments.count)),
                header: padded(builder.header), rows: builder.rows.map(padded)))
    }
}

// MARK: Plain text

extension MarkdownBlocks {
    private static let ruleText = String(repeating: "\u{2500}", count: 20)

    /// The document as text without Markdown's markers: headings as their text, list items
    /// with "•" or their number, links as "text (url)", table cells separated by tabs.
    public static func plainText(_ blocks: [MarkdownBlock]) -> String {
        var out = ""
        var previous: MarkdownBlock?
        for block in blocks {
            if let previous { out += sameList(previous, block) ? "\n" : "\n\n" }
            out += plainLines(block)
            previous = block
        }
        return out.isEmpty ? out : out + "\n"
    }

    /// The next item of the same list (or of a list nested in it) follows on the next line.
    public static func sameList(_ previous: MarkdownBlock, _ block: MarkdownBlock) -> Bool {
        guard previous.listDepth > 0, block.listDepth > 0, block.quoteDepth == previous.quoteDepth
        else { return false }
        return !block.startsList || block.listDepth > previous.listDepth
    }

    private static func plainLines(_ block: MarkdownBlock) -> String {
        let quote = String(repeating: " ", count: 4 * block.quoteDepth)
        let list = String(repeating: " ", count: 3 * max(0, block.listDepth - 1))
        let body: String
        switch block.kind {
        case .thematicBreak:
            body = ruleText
        case .table(let table):
            body = ([table.header] + table.rows)
                .map { $0.map(plainInline).joined(separator: "\t") }
                .joined(separator: "\n")
        case .code:
            body = block.spans.map(\.text).joined()
                .components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
        case .heading, .paragraph:
            body = plainInline(block.spans)
        }
        var lines = body.components(separatedBy: "\n")
        if block.listDepth > 0 {
            let marker = block.marker.map { $0.padding(toLength: max(3, $0.count + 1),
                                                         withPad: " ", startingAt: 0) }
            let hang = String(repeating: " ", count: max(3, (marker?.count ?? 3)))
            lines = lines.enumerated().map { index, line in
                index == 0 ? list + (marker ?? hang) + line : list + hang + line
            }
        }
        return lines.map { line in
            let indented = quote + line
            return indented.trimmingCharacters(in: .whitespaces).isEmpty ? "" : indented
        }.joined(separator: "\n")
    }

    /// Spans as text; a link shows its address unless the text already is the address.
    public static func plainInline(_ spans: [MarkdownSpan]) -> String {
        spans.map { span in
            guard let link = span.link else { return span.text }
            let address = link.absoluteString
            let bare = address.replacingOccurrences(
                of: "^(https?://|mailto:)", with: "", options: .regularExpression)
            return span.text == address || span.text == bare
                ? span.text : "\(span.text) (\(address))"
        }.joined()
    }
}
