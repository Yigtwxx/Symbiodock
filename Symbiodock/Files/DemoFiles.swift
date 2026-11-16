#if DEBUG
import AppKit
import SymbiodockCore

/// A fixed shelf for looking at the Files tab without dropping anything:
/// `open --env SYMBIODOCK_DEMO_FILES=1 build/Build/Products/Debug/Symbiodock.app`.
/// A drawer of three documents, picked whole, then five lone files. `converting` then presses
/// `PDF` for the drawer: its two documents pretend to become PDFs and the column says
/// `Slides.pptx can't become PDF`. The files are not there: their pictures and sizes are made
/// here, and a demo shelf is never saved.
///
/// `SYMBIODOCK_CONVERT=<path> SYMBIODOCK_CONVERT_TO=<chip label>` runs one conversion without
/// the island, prints `converted: <path>` or `failed: <message>` and exits 0 / 1 (see
/// `ConvertHook`). Several paths separated by `:` with `ZIP` call `archive`.
/// `SYMBIODOCK_CONVERT_CANCEL_AFTER=<seconds>` cancels it part way.
///
/// `SYMBIODOCK_FLOW=<path>:<path>… SYMBIODOCK_FLOW_TO=<chip label>` plays a press of the chip
/// through the shelf's whole flow without the island and prints what changes (see `FlowHook`).
///
/// `SYMBIODOCK_ADD_FILE=<path>` puts that file on the real shelf at launch, as a drop would:
/// run once with it, quit, run again without it, and the log line "restored 1 items" (category
/// `shelf`) shows that the shelf came back. It stays as a test hook.
@MainActor
enum DemoFiles {
    static var requested: String? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_FILES"].flatMap {
            ["1", "converting"].contains($0) ? $0 : nil
        }
    }

    static var fileToAdd: URL? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_ADD_FILE"].map {
            URL(fileURLWithPath: $0)
        }
    }

    /// Lays out the demo shelf; for `converting`, returns the chip press to play on it.
    @discardableResult
    static func apply(_ set: String, to state: IslandState, previews: FilePreviews) -> FileRequest? {
        let drawer = UUID()
        let stacked = ["Report.docx", "Notes.docx", "Slides.pptx"].map { item($0, stack: drawer) }
        let lone = ["Holiday.heic", "Invoice.pdf", "Mix.wav", "Clip.mov", "Photos/"].map { item($0) }
        state.restoreShelf(stacked + lone)
        state.selectShelfItems(stacked.map(\.id))
        stage(state.shelf.items, in: previews)
        return set == "converting" ? .convert(stacked.map(\.id), label: "PDF") : nil
    }

    /// A file on a desktop that does not exist; a trailing slash makes a folder.
    static func item(_ name: String, stack: UUID? = nil) -> ShelfItem {
        let isDirectory = name.hasSuffix("/")
        let desktop = URL(fileURLWithPath: "/Users/demo/Desktop", isDirectory: true)
        return ShelfItem(
            url: desktop.appendingPathComponent(name.trimmingCharacters(in: ["/"])),
            isDirectory: isDirectory, stack: stack)
    }

    /// What real files would show: a photo, two pages, and plausible sizes (none for a folder).
    static func stage(_ items: [ShelfItem], in previews: FilePreviews) {
        for item in items {
            previews.stage(item, image: DemoPictures.image(for: item.name), bytes: sizes[item.name])
        }
    }

    private static let sizes: [String: Int64] = [
        "Report.docx": 1_240_000, "Notes.docx": 86_000, "Slides.pptx": 2_810_000,
        "Holiday.heic": 3_420_000, "Invoice.pdf": 248_000, "Mix.wav": 31_700_000,
        "Clip.mov": 58_200_000, "Archive.zip": 12_400_000,
    ]
}

/// Pictures drawn in code for demo files: a sunset photo, a report's page, an invoice. Drawn
/// at whatever scale they are shown, so they are as sharp as real thumbnails.
private enum DemoPictures {
    static func image(for name: String) -> NSImage? {
        switch name {
        case "Holiday.heic": photo
        case "Report.docx": page(drawReport)
        case "Invoice.pdf": page(drawInvoice)
        default: nil
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1)
        -> NSColor
    {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    /// A sun low over the sea, a headland on the left.
    private static var photo: NSImage {
        NSImage(size: CGSize(width: 160, height: 120), flipped: false) { rect in
            let horizon = rect.height * 0.36
            let sky = CGRect(x: 0, y: horizon, width: rect.width, height: rect.height - horizon)
            NSGradient(
                colors: [rgb(255, 205, 140), rgb(245, 130, 105), rgb(150, 80, 140), rgb(40, 44, 110)],
                atLocations: [0, 0.22, 0.58, 1], colorSpace: .sRGB)?
                .draw(in: sky, angle: 90)
            let sun = CGPoint(x: rect.width * 0.63, y: horizon + 15)
            NSGradient(starting: rgb(255, 225, 170, 0.9), ending: rgb(255, 160, 110, 0))?
                .draw(fromCenter: sun, radius: 0, toCenter: sun, radius: 52, options: [])
            rgb(255, 240, 205).setFill()
            NSBezierPath(ovalIn: CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22)).fill()
            NSGradient(starting: rgb(22, 30, 70), ending: rgb(85, 70, 120))?
                .draw(in: CGRect(x: 0, y: 0, width: rect.width, height: horizon), angle: 90)
            // The sun's path on the water: shorter, fainter streaks towards the shore.
            for step in 0..<8 {
                let width = 30 - CGFloat(step) * 3
                let y = horizon - 3 - CGFloat(step) * 5
                rgb(255, 215, 160, 0.75 - CGFloat(step) * 0.08).setFill()
                NSBezierPath(
                    roundedRect: CGRect(x: sun.x - width / 2, y: y, width: width, height: 1.6),
                    xRadius: 0.8, yRadius: 0.8
                ).fill()
            }
            let land = NSBezierPath()
            land.move(to: CGPoint(x: 0, y: horizon - 4))
            land.line(to: CGPoint(x: 0, y: horizon + 26))
            land.curve(
                to: CGPoint(x: 46, y: horizon + 6), controlPoint1: CGPoint(x: 18, y: horizon + 30),
                controlPoint2: CGPoint(x: 30, y: horizon + 10))
            land.curve(
                to: CGPoint(x: 70, y: horizon), controlPoint1: CGPoint(x: 56, y: horizon + 3),
                controlPoint2: CGPoint(x: 62, y: horizon + 1))
            land.line(to: CGPoint(x: 0, y: horizon - 4))
            rgb(28, 22, 48).setFill()
            land.fill()
            return true
        }
    }

    /// A white sheet in A4 proportions; `content` draws on it with the origin at the top-left.
    private static func page(_ content: @escaping @Sendable (CGRect) -> Void) -> NSImage {
        NSImage(size: CGSize(width: 85, height: 120), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            content(rect.insetBy(dx: 9, dy: 10))
            return true
        }
    }

    private static func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: CGRect(x: x, y: y, width: width, height: height),
            xRadius: height / 2, yRadius: height / 2
        ).fill()
    }

    /// A title, a figure and paragraphs of grey lines.
    private static func drawReport(_ area: CGRect) {
        let ink = rgb(60, 60, 67)
        let text = rgb(199, 199, 204)
        bar(area.minX, area.minY, area.width * 0.62, 5, ink)
        bar(area.minX, area.minY + 9, area.width * 0.38, 3, rgb(10, 132, 255, 0.8))
        var y = area.minY + 19
        for width in [1, 0.94, 0.98, 0.7] as [CGFloat] {
            bar(area.minX, y, area.width * width, 2.2, text)
            y += 5
        }
        y += 3
        rgb(229, 229, 234).setFill()
        NSBezierPath(
            roundedRect: CGRect(x: area.minX, y: y, width: area.width, height: 26), xRadius: 2,
            yRadius: 2
        ).fill()
        for (index, height) in [10, 16, 13, 21, 18].enumerated() {
            rgb(10, 132, 255, 0.55).setFill()
            CGRect(
                x: area.minX + 6 + CGFloat(index) * 11, y: y + 26 - 3 - CGFloat(height), width: 6,
                height: CGFloat(height)
            ).fill()
        }
        y += 32
        for width in [0.96, 1, 0.9, 0.97, 0.6, 0.93, 0.85] as [CGFloat] where y < area.maxY {
            bar(area.minX, y, area.width * width, 2.2, text)
            y += 5
        }
    }

    /// A logo and a heading, two addresses, a table of items and a total.
    private static func drawInvoice(_ area: CGRect) {
        let ink = rgb(60, 60, 67)
        let text = rgb(199, 199, 204)
        rgb(255, 69, 58).setFill()
        NSBezierPath(
            roundedRect: CGRect(x: area.minX, y: area.minY, width: 11, height: 11), xRadius: 3,
            yRadius: 3
        ).fill()
        bar(area.maxX - area.width * 0.42, area.minY + 1, area.width * 0.42, 5, ink)
        bar(area.maxX - area.width * 0.26, area.minY + 9, area.width * 0.26, 2.2, text)
        var y = area.minY + 20
        for width in [0.4, 0.32, 0.36] as [CGFloat] {
            bar(area.minX, y, area.width * width, 2.2, text)
            bar(area.maxX - area.width * width, y, area.width * width, 2.2, text)
            y += 4.5
        }
        y += 6
        rgb(242, 242, 247).setFill()
        CGRect(x: area.minX, y: y, width: area.width, height: 7).fill()
        bar(area.minX + 2, y + 2.4, area.width * 0.3, 2.2, rgb(142, 142, 147))
        y += 11
        for width in [0.5, 0.42, 0.56, 0.38, 0.47] as [CGFloat] {
            bar(area.minX + 2, y, area.width * width, 2.2, text)
            bar(area.maxX - 14, y, 12, 2.2, text)
            y += 4
            rgb(229, 229, 234).setFill()
            CGRect(x: area.minX, y: y, width: area.width, height: 0.5).fill()
            y += 3
        }
        y += 2
        bar(area.maxX - area.width * 0.45, y, area.width * 0.2, 3, ink)
        bar(area.maxX - 18, y, 16, 3, rgb(255, 69, 58))
    }
}

/// Runs one conversion headless and exits by itself; the way to try the converters without
/// a tile to press. Nothing is shown, so no window or permission dialog can appear.
@MainActor
enum ConvertHook {
    /// True when the hook took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let paths = environment["SYMBIODOCK_CONVERT"],
            let chip = environment["SYMBIODOCK_CONVERT_TO"]
        else { return false }
        let sources = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let cancelAfter = environment["SYMBIODOCK_CONVERT_CANCEL_AFTER"].flatMap(Double.init)
        let converter = FileConverter(runner: ToolRunner(helpers: HelperProcesses()))

        let work = Task { () -> String? in
            do {
                if chip == "ZIP" && sources.count > 1 {
                    return "converted: \(try await converter.archive(sources).path)"
                }
                guard let source = sources.first else { return nil }
                let isDirectory =
                    (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let targets = ConversionCatalog.targets(
                    pathExtension: source.pathExtension, isDirectory: isDirectory)
                guard let target = targets.first(where: { $0.label == chip }) else {
                    return "failed: no such chip"
                }
                let result = try await converter.convert(
                    source, isDirectory: isDirectory, to: target)
                return "converted: \(result.url.path)"
            } catch is CancellationError {
                return "failed: cancelled"
            } catch let failure as ConversionFailure {
                return "failed: \(failure.message)"
            } catch {
                return "failed: unknown"
            }
        }
        if let cancelAfter {
            Task {
                try? await Task.sleep(for: .seconds(cancelAfter))
                work.cancel()
            }
        }
        Task {
            let line = await work.value ?? "failed: nothing to convert"
            print(line)
            fflush(stdout)
            exit(line.hasPrefix("converted") ? 0 : 1)
        }
        return true
    }
}

/// Plays a press of a chip through the shelf's flow headless and exits by itself: what a tile
/// goes through, without the island to watch it. The files go on a shelf of its own (several
/// make one stack, as a drop would); the saved shelf is not touched. One line per change the
/// island would show, with seconds since the press: `begin <name>`, `reveal <name> -> <name
/// the tile shows now>`, `leave <name>`, `notice <text>`, `end <name>`; once no conversion is
/// left, `shelf: <names>`, and exit 0. `SYMBIODOCK_FLOW_CANCEL_AFTER=<seconds>` presses Cancel;
/// `SYMBIODOCK_FLOW_APART=1` puts each file on a tile of its own (the last one given in front);
/// `SYMBIODOCK_FLOW_REMOVE_AFTER=<seconds>` presses `Remove` on the shelf's first file then.
/// `SYMBIODOCK_FLOW=demo` plays the `converting` demo instead, without a chip.
@MainActor
enum FlowHook {
    /// Kept alive until the process exits: the batches hold their coordinator weakly.
    private static var running: (ShelfCoordinator, FlowPrinter)?

    /// True when the hook took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let paths = environment["SYMBIODOCK_FLOW"],
            paths == "demo" || environment["SYMBIODOCK_FLOW_TO"] != nil
        else { return false }
        let state = IslandState()
        let previews = FilePreviews()
        let shelf = ShelfCoordinator(
            state: state, previews: previews,
            converter: FileConverter(runner: ToolRunner(helpers: HelperProcesses())))
        shelf.persists = false
        let request: FileRequest?
        if paths == "demo" {
            shelf.isDemo = true
            request = DemoFiles.apply("converting", to: state, previews: previews)
        } else {
            let urls = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
            if environment["SYMBIODOCK_FLOW_APART"] == "1" {
                urls.forEach { shelf.add([$0]) }
            } else {
                shelf.add(urls)
            }
            request = environment["SYMBIODOCK_FLOW_TO"].map { .convert(state.shelf.items.map(\.id), label: $0) }
        }
        let printer = FlowPrinter(state: state)
        running = (shelf, printer)
        printer.watch()
        if let request { shelf.handle(request) }
        // Nothing covered and nothing said: no change will come to end the run.
        if state.conversions.isEmpty { Task { printer.changed() } }
        if let after = environment["SYMBIODOCK_FLOW_CANCEL_AFTER"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(after))
                shelf.handle(.cancel(state.shelf.items.map(\.id)))
            }
        }
        if let after = environment["SYMBIODOCK_FLOW_REMOVE_AFTER"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(after))
                if let first = state.shelf.items.first { shelf.handle(.remove([first.id])) }
            }
        }
        return true
    }
}

/// Prints the changes of the shelf's state as `FlowHook` describes them.
@MainActor
private final class FlowPrinter {
    private let state: IslandState
    private let start = Date()
    /// What was printed last: the conversions, the files with the names they showed, the notice.
    private var conversions: [UUID: FileConversion] = [:]
    private var shown: [(id: UUID, name: String)]
    private var notice: ShelfNotice?

    init(state: IslandState) {
        self.state = state
        shown = state.shelf.items.map { ($0.id, Self.name($0)) }
        notice = state.shelfNotice
    }

    func watch() {
        withObservationTracking {
            _ = state.conversions
            _ = state.shelf
            _ = state.shelfNotice
        } onChange: { [weak self] in
            // Told before the change: look once the change is made.
            Task { @MainActor in self?.changed() }
        }
    }

    func changed() {
        let now = state.conversions
        let held = Dictionary(state.shelf.items.map { ($0.id, Self.name($0)) }) { first, _ in first }
        var lines: [String] = []
        for (id, name) in shown {
            if let conversion = now[id], conversions[id] == nil {
                lines.append(line(at: conversion.started, "begin \(name)"))
            }
        }
        for (id, name) in shown {
            guard let opened = now[id]?.revealStarted, conversions[id]?.revealStarted == nil else { continue }
            let showing = held[id].map { $0 == name ? "unchanged" : $0 } ?? "gone"
            lines.append(line(at: opened, "reveal \(name) -> \(showing)"))
        }
        for (id, name) in shown where held[id] == nil { lines.append(line(at: Date(), "leave \(name)")) }
        if let next = state.shelfNotice, next != notice { lines.append(line(at: Date(), "notice \(next.text)")) }
        for (id, name) in shown where conversions[id] != nil && now[id] == nil && held[id] != nil {
            lines.append(line(at: Date(), "end \(name)"))
        }
        lines.forEach { print($0) }
        conversions = now
        shown = state.shelf.items.map { ($0.id, Self.name($0)) }
        notice = state.shelfNotice
        guard now.isEmpty else { return watch() }
        print("shelf: " + shown.map(\.name).joined(separator: ", "))
        fflush(stdout)
        exit(0)
    }

    private func line(at date: Date, _ text: String) -> String {
        String(format: "%6.3f ", date.timeIntervalSince(start)) + text
    }

    /// A folder ends in "/", as it would in a listing.
    private static func name(_ item: ShelfItem) -> String {
        item.isDirectory ? item.name + "/" : item.name
    }
}
#endif
