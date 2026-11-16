import AppKit
import SymbiodockCore

/// Documents to PDF through the same printing path as Print > Save as PDF, run without panels.
/// textutil cannot make PDF; this is the one conversion that has to touch AppKit.
enum DocumentPDFWriter {
    struct Failure: Error {}

    private static let margin: CGFloat = 56

    @MainActor
    static func write(_ source: URL, sourceExtension: String, to output: URL) throws {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin

        // Markdown is typeset from the system's parser; plain text is printed as it is.
        let text: NSAttributedString
        let isPlain = sourceExtension == "txt"
        if sourceExtension == "md" {
            let blocks = MarkdownBlocks.parse(try MarkdownDocument.readSource(source))
            text = MarkdownDocument.attributed(blocks, width: width, target: .print)
        } else {
            text = try read(source, plain: isPlain)
        }

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.drawsBackground = true
        view.backgroundColor = .white
        // Links keep the colour the document gave them.
        view.linkTextAttributes = [:]
        view.textStorage?.setAttributedString(text)
        // Plain text takes the system colors, which are white in dark mode: print it black.
        if isPlain {
            view.textStorage?.addAttribute(
                .foregroundColor, value: NSColor.black,
                range: NSRange(location: 0, length: view.textStorage?.length ?? 0))
        }
        if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            view.setFrameSize(NSSize(width: width, height: max(used.height, 100)))
        }

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw Failure() }
    }

    /// A document as AppKit reads it. Plain text is UTF-8 first; the system's own guess would
    /// read Turkish letters as Mac Roman.
    private static func read(_ source: URL, plain: Bool) throws -> NSAttributedString {
        guard plain else {
            return try NSAttributedString(url: source, options: [:], documentAttributes: nil)
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.plain
        ]
        do {
            var utf8 = options
            utf8[.characterEncoding] = String.Encoding.utf8.rawValue
            return try NSAttributedString(url: source, options: utf8, documentAttributes: nil)
        } catch {
            // Not valid UTF-8: let the system detect the encoding.
            return try NSAttributedString(url: source, options: options, documentAttributes: nil)
        }
    }
}
