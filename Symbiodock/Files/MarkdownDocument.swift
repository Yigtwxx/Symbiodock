import AppKit
import SymbiodockCore

/// Markdown as a typeset document: the system parser's blocks (`MarkdownBlocks`) set with real
/// fonts and paragraph styles, because AppKit does not lay out the parser's block structure by
/// itself. Printed to PDF by `DocumentPDFWriter`; written to DOCX, RTF, HTML and ODT here.
enum MarkdownDocument {
    struct Failure: Error {}

    /// Where the text goes, which decides what AppKit can carry there.
    enum Target {
        /// Printed to PDF: the system font, code and quotes in text blocks (a filled box, a
        /// bar on the left).
        case print
        /// HTML: the text blocks become styled `div`s and lists real `ul`/`ol` lists.
        case html
        /// DOCX, RTF, ODT: their writers turn text blocks into tables (RTF) or drop their
        /// spacing (DOCX, ODT), so code and quotes are set with indents and shading instead,
        /// and lists stay as their typed markers.
        case document

        var usesTextBlocks: Bool { self != .document }
        var usesTextLists: Bool { self == .html }
    }

    /// Text width of an exported document: a Letter page with one-inch margins.
    static let exportWidth: CGFloat = 468

    // MARK: Reading and writing

    /// UTF-8 first; the system's own guess would read Turkish letters as Mac Roman. Text that
    /// is not UTF-8 falls back to the system's detection.
    static func readSource(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        let plain = try NSAttributedString(
            url: url, options: [.documentType: NSAttributedString.DocumentType.plain],
            documentAttributes: nil)
        return plain.string
    }

    /// Writes `source` as `format` ("docx", "rtf", "txt", "html" or "odt") to `output`.
    static func write(_ source: URL, format: String, to output: URL) throws {
        let blocks = MarkdownBlocks.parse(try readSource(source))
        if format == "txt" {
            try Data(MarkdownBlocks.plainText(blocks).utf8).write(to: output)
            return
        }
        let type: NSAttributedString.DocumentType
        switch format {
        case "docx": type = .officeOpenXML
        case "rtf": type = .rtf
        case "html": type = .html
        case "odt": type = .openDocument
        default: throw Failure()
        }
        let text = attributed(
            blocks, width: exportWidth, target: type == .html ? .html : .document)
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        if type == .html {
            attributes[.characterEncoding] = String.Encoding.utf8.rawValue
            attributes[.title] = source.deletingPathExtension().lastPathComponent
        }
        let data = try text.data(
            from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
        try data.write(to: output)
    }

    // MARK: Typesetting

    private static let bodySize: CGFloat = 12
    private static let codeSize: CGFloat = 10.5
    private static let headingSizes: [CGFloat] = [22, 17, 14, 12.5, 12, 12]
    private static let headingSpace: [CGFloat] = [22, 18, 14, 12, 12, 12]
    private static let blockSpace: CGFloat = 10
    private static let listStep: CGFloat = 22
    private static let quoteStep: CGFloat = 17
    private static let codeInset: CGFloat = 12

    private static let ink = NSColor.black
    private static let quoteInk = NSColor(white: 0.36, alpha: 1)
    private static let linkInk = NSColor(srgbRed: 0.04, green: 0.34, blue: 0.82, alpha: 1)
    private static let codeFill = NSColor(white: 0.955, alpha: 1)
    private static let codeEdge = NSColor(white: 0.86, alpha: 1)
    private static let quoteBar = NSColor(white: 0.80, alpha: 1)
    private static let ruleInk = NSColor(white: 0.75, alpha: 1)

    private struct Fonts {
        let body: NSFont
        let mono: NSFont

        /// A PDF embeds its fonts and can use the system font; a document opened elsewhere
        /// names fonts other systems have or replace sensibly.
        init(_ target: Target) {
            if target == .print {
                body = .systemFont(ofSize: MarkdownDocument.bodySize)
                mono = .monospacedSystemFont(ofSize: MarkdownDocument.codeSize, weight: .regular)
            } else {
                body = NSFont(name: "Helvetica Neue", size: MarkdownDocument.bodySize)
                    ?? .systemFont(ofSize: MarkdownDocument.bodySize)
                mono = NSFont(name: "Menlo", size: MarkdownDocument.codeSize)
                    ?? .monospacedSystemFont(ofSize: MarkdownDocument.codeSize, weight: .regular)
            }
        }

        func sized(_ font: NSFont, _ size: CGFloat) -> NSFont {
            NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        }

        func styled(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
            var traits = font.fontDescriptor.symbolicTraits
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            guard traits != font.fontDescriptor.symbolicTraits else { return font }
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits),
                          size: font.pointSize) ?? font
        }
    }

    /// What one block is set with besides its own kind.
    private struct Context {
        let target: Target
        let fonts: Fonts
        let width: CGFloat
        /// Space above the block; 0 when an enclosing text block already holds it.
        var space: CGFloat
        var quotes: [NSTextBlock]
        var lists: [NSTextList]
    }

    /// The blocks as one attributed string, black on white, `width` points wide.
    static func attributed(_ blocks: [MarkdownBlock], width: CGFloat, target: Target)
        -> NSAttributedString
    {
        let fonts = Fonts(target)
        let out = NSMutableAttributedString()
        var previous: MarkdownBlock?
        var quotes: [NSTextBlock] = []
        var lists: [NSTextList] = []

        for block in blocks {
            var space = spaceBefore(block, after: previous)

            // A quote is a text block with a bar on its left; its first paragraph's space goes
            // outside the block so the bar starts with the text.
            if target.usesTextBlocks {
                if quotes.count > block.quoteDepth {
                    quotes.removeLast(quotes.count - block.quoteDepth)
                }
                while quotes.count < block.quoteDepth {
                    quotes.append(quoteBlock(space: space, outermost: quotes.isEmpty))
                    space = 0
                }
            }

            // One NSTextList per level, so HTML keeps real lists.
            if lists.count > block.listDepth { lists.removeLast(lists.count - block.listDepth) }
            if block.startsList, block.listDepth > 0 {
                lists.removeLast(max(0, lists.count - (block.listDepth - 1)))
            }
            while lists.count < block.listDepth {
                lists.append(textList(for: block))
            }

            let context = Context(
                target: target, fonts: fonts, width: width, space: space, quotes: quotes,
                lists: target.usesTextLists ? lists : [])
            out.append(render(block, context))
            previous = block
        }
        // Every block ends its paragraph; the last one needs no empty line after it.
        if out.string.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    private static func quoteBlock(space: CGFloat, outermost: Bool) -> NSTextBlock {
        let quote = NSTextBlock()
        quote.setValue(100, type: .percentageValueType, for: .width)
        quote.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        quote.setBorderColor(quoteBar, for: .minX)
        quote.setWidth(quoteStep - 5, type: .absoluteValueType, for: .padding, edge: .minX)
        quote.setWidth(outermost ? 2 : 0, type: .absoluteValueType, for: .margin, edge: .minX)
        quote.setWidth(space, type: .absoluteValueType, for: .margin, edge: .minY)
        quote.setWidth(2, type: .absoluteValueType, for: .padding, edge: .minY)
        quote.setWidth(2, type: .absoluteValueType, for: .padding, edge: .maxY)
        return quote
    }

    private static func textList(for block: MarkdownBlock) -> NSTextList {
        guard let marker = block.marker, marker != "•" else {
            return NSTextList(markerFormat: .disc, options: 0)
        }
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = Int(marker.dropLast()) ?? 1
        return list
    }

    private static func spaceBefore(_ block: MarkdownBlock, after previous: MarkdownBlock?)
        -> CGFloat
    {
        guard let previous else { return 0 }
        if case .heading(let level) = block.kind { return headingSpace[level - 1] }
        if case .heading(let level) = previous.kind { return level == 1 ? 8 : 6 }
        if MarkdownBlocks.sameList(previous, block) {
            return block.marker == nil ? 5 : 3
        }
        return blockSpace
    }

    private static func paragraphStyle(_ context: Context, space: CGFloat? = nil)
        -> NSMutableParagraphStyle
    {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = space ?? context.space
        style.paragraphSpacing = 0
        style.lineHeightMultiple = 1.2
        style.textBlocks = context.quotes
        return style
    }

    private static func render(_ block: MarkdownBlock, _ context: Context) -> NSAttributedString {
        let fonts = context.fonts
        let color = block.quoteDepth > 0 ? quoteInk : ink
        // Without text blocks a quote is only an indent.
        let lead = context.target.usesTextBlocks ? 0 : CGFloat(block.quoteDepth) * quoteStep
        let indent = lead + CGFloat(block.listDepth) * listStep
        let available =
            context.width - indent
            - (context.target.usesTextBlocks ? CGFloat(block.quoteDepth) * quoteStep : 0)

        switch block.kind {
        case .heading(let level):
            let style = paragraphStyle(context)
            style.lineHeightMultiple = 1.1
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            let font = fonts.styled(
                fonts.sized(fonts.body, headingSizes[level - 1]), bold: true, italic: false)
            let text = inline(block.spans, font: font, fonts: fonts, color: color)
            return paragraph(text, style: style, font: font, color: color)

        case .paragraph:
            let style = paragraphStyle(context)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            let text = NSMutableAttributedString()
            if block.listDepth > 0, let marker = block.marker {
                // TextEdit's own list layout: "\t•\t", the marker right-aligned before the
                // text, so numbers line up on their dots. The DOCX writer drops tab stops, so
                // documents start with the marker and let the hanging indent stop the tab.
                style.textLists = context.lists
                style.firstLineHeadIndent = indent - listStep
                let lead = context.target == .document ? "" : "\t"
                style.tabStops =
                    (lead.isEmpty ? [] : [NSTextTab(textAlignment: .right, location: indent - 7)])
                    + [NSTextTab(textAlignment: .left, location: indent)]
                let markerFont = marker == "•" ? fonts.body : fonts.body.monospacedDigits
                text.append(NSAttributedString(
                    string: "\(lead)\(marker)\t",
                    attributes: [.font: markerFont, .foregroundColor: color]))
            } else if block.listDepth > 0 {
                style.textLists = context.lists
            }
            text.append(inline(block.spans, font: fonts.body, fonts: fonts, color: color))
            return paragraph(text, style: style, font: fonts.body, color: color)

        case .code:
            return code(block, context, indent: indent)

        case .thematicBreak:
            return rule(context, indent: indent, available: available)

        case .table(let table):
            return render(table, context, indent: indent, available: available, color: color)
        }
    }

    /// Code keeps its lines and spaces (tabs as four spaces) in the monospaced font: in a
    /// filled, ruled box where text blocks work, else indented on a shaded background.
    private static func code(_ block: MarkdownBlock, _ context: Context, indent: CGFloat)
        -> NSAttributedString
    {
        let source = block.spans.map(\.text).joined()
            .replacingOccurrences(of: "\t", with: "    ")
        let lines = source.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        if context.target.usesTextBlocks {
            let box = NSTextBlock()
            box.setValue(100, type: .percentageValueType, for: .width)
            box.backgroundColor = codeFill
            box.setWidth(0.5, type: .absoluteValueType, for: .border)
            box.setBorderColor(codeEdge)
            box.setWidth(9, type: .absoluteValueType, for: .padding)
            // The space above sits in a clear block around it: a filled block paints its own
            // margin too.
            let frame = NSTextBlock()
            frame.setValue(100, type: .percentageValueType, for: .width)
            frame.setWidth(context.space, type: .absoluteValueType, for: .margin, edge: .minY)
            frame.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX)
            var boxed = context
            boxed.quotes += [frame, box]
            let style = paragraphStyle(boxed, space: 0)
            style.lineHeightMultiple = 1.15
            style.lineBreakMode = .byCharWrapping
            out.append(NSAttributedString(
                string: source + "\n",
                attributes: [.font: context.fonts.mono, .foregroundColor: ink,
                             .paragraphStyle: style]))
            return out
        }
        for (index, line) in lines.enumerated() {
            let style = paragraphStyle(context, space: index == 0 ? context.space : 0)
            style.lineHeightMultiple = 1.15
            style.firstLineHeadIndent = indent + codeInset
            style.headIndent = indent + codeInset
            style.lineBreakMode = .byCharWrapping
            // A non-breaking space keeps an empty line shaded and at full height.
            out.append(NSAttributedString(
                string: (line.isEmpty ? "\u{00A0}" : line) + "\n",
                attributes: [.font: context.fonts.mono, .foregroundColor: ink,
                             .backgroundColor: codeFill, .paragraphStyle: style]))
        }
        return out
    }

    /// A hairline from the margin to the right edge where text blocks work (a tab struck
    /// through to a stop at the edge), else a centered row of dots that every format keeps.
    private static func rule(_ context: Context, indent: CGFloat, available: CGFloat)
        -> NSAttributedString
    {
        let style = paragraphStyle(context)
        style.lineHeightMultiple = 1
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        guard context.target == .print else {
            style.alignment = .center
            return NSAttributedString(
                string: "\u{2022}   \u{2022}   \u{2022}\n",
                attributes: [.font: context.fonts.body, .foregroundColor: ruleInk,
                             .paragraphStyle: style])
        }
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent + available - 8)]
        // The no-break space keeps the tab from being trailing white space, which is never
        // struck.
        return NSAttributedString(
            string: "\t\u{00A0}\n",
            attributes: [
                .font: context.fonts.sized(context.fonts.body, 7), .foregroundColor: ruleInk,
                .paragraphStyle: style,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: ruleInk,
            ])
    }

    /// Rows of tab-separated cells on stops measured from the widest cell of each column;
    /// the header is bold, and ruled off where text blocks work.
    private static func render(
        _ table: MarkdownTable, _ context: Context, indent: CGFloat, available: CGFloat,
        color: NSColor
    ) -> NSAttributedString {
        let fonts = context.fonts
        let bold = fonts.styled(fonts.body, bold: true, italic: false)
        let header = table.header.map { inline($0, font: bold, fonts: fonts, color: color) }
        let rows = table.rows.map { row in
            row.map { inline($0, font: fonts.body, fonts: fonts, color: color) }
        }
        let columns = table.alignments.count
        var widths = Array(repeating: CGFloat(0), count: columns)
        for row in [header] + rows {
            for (column, cell) in row.enumerated() where column < columns {
                widths[column] = max(widths[column], ceil(cell.size().width))
            }
        }
        let total = widths.reduce(0, +)
        let gap = columns > 1 ? min(24, max(8, (available - total) / CGFloat(columns - 1))) : 0
        var starts: [CGFloat] = []
        var x = indent
        for width in widths {
            starts.append(x)
            x += width + gap
        }
        let tableWidth = x - gap - indent
        var stops: [NSTextTab] = []
        for column in 0..<columns {
            switch table.alignments[column] {
            case .left:
                if column > 0 {
                    stops.append(NSTextTab(textAlignment: .left, location: starts[column]))
                }
            case .center:
                stops.append(NSTextTab(textAlignment: .center,
                                       location: starts[column] + widths[column] / 2))
            case .right:
                stops.append(NSTextTab(textAlignment: .right,
                                       location: starts[column] + widths[column]))
            }
        }

        let out = NSMutableAttributedString()
        for (index, row) in ([header] + rows).enumerated() {
            let isHeader = index == 0
            var rowContext = context
            var space: CGFloat = index == 1 ? 4 : 2
            if isHeader {
                space = context.space
                if context.target.usesTextBlocks {
                    let rule = NSTextBlock()
                    rule.setValue(indent + tableWidth, type: .absoluteValueType, for: .width)
                    rule.setWidth(0.75, type: .absoluteValueType, for: .border, edge: .maxY)
                    rule.setBorderColor(ruleInk, for: .maxY)
                    rule.setWidth(3, type: .absoluteValueType, for: .padding, edge: .maxY)
                    rule.setWidth(space, type: .absoluteValueType, for: .margin, edge: .minY)
                    rowContext.quotes.append(rule)
                    space = 0
                }
            }
            let style = paragraphStyle(rowContext, space: space)
            style.tabStops = stops
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            let line = NSMutableAttributedString()
            for (column, cell) in row.enumerated() where column < columns {
                if column > 0 || table.alignments[column] != .left {
                    line.append(NSAttributedString(string: "\t", attributes: [.font: fonts.body]))
                }
                line.append(cell)
            }
            out.append(paragraph(line, style: style, font: isHeader ? bold : fonts.body,
                                 color: color))
        }
        return out
    }

    /// `text` closed with a newline, the paragraph style over all of it.
    private static func paragraph(
        _ text: NSAttributedString, style: NSParagraphStyle, font: NSFont, color: NSColor
    ) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        out.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }

    /// Spans in `font`, bold, italic, struck, code and links set on top. A hard break stays
    /// inside the paragraph as a line separator.
    private static func inline(
        _ spans: [MarkdownSpan], font: NSFont, fonts: Fonts, color: NSColor
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for span in spans {
            var spanFont = font
            if span.style.contains(.code) {
                spanFont = fonts.sized(fonts.mono, font.pointSize * 0.9)
            }
            spanFont = fonts.styled(
                spanFont, bold: span.style.contains(.bold), italic: span.style.contains(.italic))
            var attributes: [NSAttributedString.Key: Any] = [
                .font: spanFont, .foregroundColor: color,
            ]
            if span.style.contains(.code) { attributes[.backgroundColor] = codeFill }
            if span.style.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = span.link {
                attributes[.link] = link
                attributes[.foregroundColor] = linkInk
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            let text = span.text.replacingOccurrences(of: "\n", with: "\u{2028}")
            out.append(NSAttributedString(string: text, attributes: attributes))
        }
        return out
    }
}

private extension NSFont {
    /// The same font with digits of one width, so list numbers line up.
    var monospacedDigits: NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
