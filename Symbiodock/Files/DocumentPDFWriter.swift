import AppKit

/// Documents to PDF through the same printing path as Print > Save as PDF, run without panels.
/// textutil cannot make PDF; this is the one conversion that has to touch AppKit.
enum DocumentPDFWriter {
    struct Failure: Error {}

    private static let margin: CGFloat = 56

    @MainActor
    static func write(_ source: URL, sourceExtension: String, to output: URL) throws {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        // Markdown is read as the plain text it is; textutil does the same for `md`.
        if sourceExtension == "md" || sourceExtension == "txt" {
            options[.documentType] = NSAttributedString.DocumentType.plain
        }
        let text = try NSAttributedString(url: source, options: options, documentAttributes: nil)

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
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.drawsBackground = true
        view.backgroundColor = .white
        view.textStorage?.setAttributedString(text)
        // Plain text takes the system colors, which are white in dark mode: print it black.
        if options[.documentType] != nil {
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
}
