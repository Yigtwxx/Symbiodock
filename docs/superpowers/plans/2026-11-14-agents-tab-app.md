# Agents Tab — App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show running AI coding agent sessions in the island: tabs in the expanded island, an Agents tab, a status mark and rim light on the collapsed island, and a click that brings a session's app forward.

**Architecture:** The core package (plan `2026-11-14-agents-tab-core.md`, all six tasks, must be finished first) holds the model, the board, the tab logic and the parsers. This plan adds what touches the system: file and process reading under `Symbiodock/Agents/`, SwiftUI views under `Symbiodock/Island/`, and the wiring in `AppDelegate`. A coordinator polls the providers off the main thread and hands the list to `IslandState`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, `libproc` and `sysctl` through `Darwin`, XcodeGen.

Spec: `docs/superpowers/specs/2026-11-14-agents-tab-design.md`.

## Global Constraints

- No third-party dependency, no new macOS permission prompt, no hook, no write outside the app's own `UserDefaults`. Nothing under `~/.claude`, `~/.codex` or any tool's directory is ever written, and no SQLite file is opened.
- Never log or print session titles, project paths, question text or process arguments. Logs carry counts, tool names and state names only.
- Interface text is English. Code, identifiers and comments are English.
- Minimum macOS 14.0. Swift 6 strict concurrency.
- Colours: red `#FF4D4F` (needs input), mint `#63E6A9` (finished), and one colour per tool for its pet. Everything else white on black.
- With Reduce Motion on, nothing travels, knocks, turns or breathes.
- Verify after every task:
  - `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1` passes.
  - `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends in `** BUILD SUCCEEDED **` with no new warning in the files the task touched.
- New Swift files under `Symbiodock/` are picked up by `xcodegen generate`; `Symbiodock.xcodeproj` is never committed.
- Commit after every task with a Conventional Commit (title ≤ 72 characters, imperative, body says why) and push to `main`.
- If code in this plan does not compile, fix it keeping behaviour and interfaces, and correct the plan in the same commit.
- Do not launch anything that shows a macOS permission dialog. Do not run `sudo`.
- To run the app: `pkill -x Symbiodock; open build/Build/Products/Debug/Symbiodock.app`. Quit it again with `pkill -x Symbiodock` when a task is done.

## File structure

| File | Responsibility |
|---|---|
| `Symbiodock/Island/Agents/AgentPalette.swift` | The state colours and each tool's colour |
| `Symbiodock/Island/Agents/AgentStatusMark.swift` | The 14 pt mark and its looks |
| `Symbiodock/Island/Agents/AgentPet.swift` | A tool's pet, drawn from bars |
| `Symbiodock/Island/Agents/AgentPetWave.swift` | A working pet as Core Animation layers: one per line, each with repeating scale and glow animations sampled from `AgentPetMotion.wave` (added after this plan; the block below quotes `AgentPet.swift` as it now is, and `AgentPetArt` there is the cache the layers reuse) |
| `Symbiodock/Island/Agents/AgentsContent.swift` | The Agents tab: rows, empty state |
| `Symbiodock/Island/Agents/AgentFaces.swift` | Collapsed faces for the notch, the capsule and the strip |
| `Symbiodock/Island/RimLight.swift` | The light along the collapsed island's rim |
| `Symbiodock/Island/FrameSchedule.swift` | How often animated views redraw (see the last section) |
| `Symbiodock/Island/LayerAnimation.swift` | Spinner and breath played by Core Animation (see the last section) |
| `Symbiodock/Island/TabStrip.swift` | The tab buttons |
| `Symbiodock/Island/ExpandedIsland.swift` | Header band plus the selected tab's content |
| `Symbiodock/Window/TabOrderStore.swift` | Tab order in `UserDefaults` |
| `Symbiodock/Agents/FileReading.swift` | Bounded head, tail and whole-file reads |
| `Symbiodock/Agents/ProcessScanner.swift` | The user's processes |
| `Symbiodock/Agents/ClaudeCodeProvider.swift` | Claude Code sessions |
| `Symbiodock/Agents/CodexProvider.swift` | Codex threads |
| `Symbiodock/Agents/HostApp.swift` | Finding and activating the app that hosts a session |
| `Symbiodock/Agents/AgentSessionCoordinator.swift` | Polling loop |
| `Symbiodock/Agents/AgentProviders.swift` | The list of providers |
| `Symbiodock/App/DebugRender.swift` | Debug only: draws the agent views to PNG files |
| `Symbiodock/Agents/DemoAgents.swift` | Debug only: a fixed set of sessions |

Modified: `IslandView.swift`, `CollapsedContent.swift`, `FloatingCollapsedContent.swift`, `SideCollapsedContent.swift`, `OverlayController.swift`, `IslandMenu.swift`, `AppDelegate.swift`.

---

### Task 1: Status mark, pets and the render harness

**Files:**
- Create: `Symbiodock/Island/Agents/AgentPalette.swift`
- Create: `Symbiodock/Island/Agents/AgentStatusMark.swift`
- Create: `Symbiodock/Island/Agents/AgentPet.swift`
- Create: `Symbiodock/App/DebugRender.swift`
- Modify (only if a figure needs tuning): `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetRelief.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `AgentRowState`, `AgentTool`, `AgentPetFigure`, `AgentPetMotion` (core).
- Produces: `AgentPalette.alert`, `AgentPalette.mint`, `AgentPalette.tint(for:strength:across:)`; `AgentStatusMark(state:size:frozenAt:)`; `AgentPet(tool:state:size:frozenAt:)`; `DebugRender.runIfRequested()`, `DebugRender.write(_:size:named:to:)`.

The pets matter to the owner more than anything else in this feature: he asked for each tool's figure to be drawn from vertical bars, in the manner of the ElevenLabs mark, each in its tool's own colour, and to look clean and beautiful. Treat Step 5 as real design work: render, look, adjust the figures in `AgentPetRelief.swift`, render again, until each figure reads at 60 pt and still reads at 18 pt.

- [ ] **Step 1: Write the palette**

`Symbiodock/Island/Agents/AgentPalette.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The colours the agents bring to the black island: two for what a session's state
/// says, and a run of colours for each tool's pet.
enum AgentPalette {
    /// A session waits for the user. #FF4D4F
    static let alert = Color(red: 1.0, green: 77.0 / 255.0, blue: 79.0 / 255.0)
    /// A session has finished. #63E6A9
    static let mint = Color(red: 99.0 / 255.0, green: 230.0 / 255.0, blue: 169.0 / 255.0)

    /// The colours a tool's pet runs through, from its upper left to its lower right, as
    /// red, green and blue from 0 to 255. None of them is the alert red or the finished mint.
    private static func run(for tool: AgentTool) -> [(Double, Double, Double)] {
        switch tool {
        case .claudeCode: [(245, 150, 95), (235, 112, 70), (205, 78, 48)]  // #F5965F #EB7046 #CD4E30
        case .codex: [(64, 150, 255), (140, 82, 255)]  // #4096FF #8C52FF
        case .geminiCLI: [(60, 135, 255), (150, 105, 255), (255, 120, 165)]  // #3C87FF #9669FF #FF78A5
        case .cursorAgent: [(250, 250, 252), (190, 190, 204)]  // #FAFAFC #BEBECC
        case .openCode: [(255, 232, 170), (240, 175, 75)]  // #FFE8AA #F0AF4B
        case .aider: [(210, 250, 70), (100, 220, 40)]  // #D2FA46 #64DC28
        case .copilotCLI: [(160, 120, 255), (255, 105, 190)]  // #A078FF #FF69BE
        }
    }

    /// A tool's colour at `position` along its run: 0 at the pet's upper left, 1 at its
    /// lower right.
    private static func components(
        for tool: AgentTool, across position: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let colors = run(for: tool)
        let place = (position.isFinite ? min(max(position, 0), 1) : 0.5) * Double(colors.count - 1)
        let lower = min(Int(place), colors.count - 2)
        let part = place - Double(lower)
        let from = colors[lower]
        let to = colors[lower + 1]
        return (
            (from.0 + (to.0 - from.0) * part) / 255, (from.1 + (to.1 - from.1) * part) / 255,
            (from.2 + (to.2 - from.2) * part) / 255
        )
    }

    /// A tool's colour at the given strength. 1 is the colour itself. Below 1 it is mixed
    /// towards the island's black, above 1 towards white (a part that glows), up to 2.
    /// The result is opaque, so that lines drawn over each other do not add up.
    static func tint(for tool: AgentTool, strength: Double = 1, across position: Double = 0.5) -> Color {
        let color = components(for: tool, across: position)
        let amount = min(max(strength, 0), 2)
        guard amount > 1 else {
            return Color(red: color.red * amount, green: color.green * amount, blue: color.blue * amount)
        }
        let white = amount - 1
        return Color(
            red: color.red + (1 - color.red) * white, green: color.green + (1 - color.green) * white,
            blue: color.blue + (1 - color.blue) * white)
    }
}
```

- [ ] **Step 2: Write the status mark**

`Symbiodock/Island/Agents/AgentStatusMark.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// One glyph for a session's state, used wherever a state is shown. Working turns, needs
/// input knocks, finished draws a check; the rest stand still.
struct AgentStatusMark: View {
    let state: AgentRowState
    var size: CGFloat = 14
    /// Draws the mark at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the mark last became finished: one ring goes outward from then.
    @State private var finishedAt: Date?

    /// The knocks and the ring are short; this is plenty for them. The working spinner is
    /// not drawn frame by frame at all: Core Animation turns it (`SpinningArc`).
    private static let frameInterval = 1.0 / 20.0
    /// The knocks and their rings are over this long into each beat; the mark rests after.
    private static let knockWindow: TimeInterval = 1.25
    private static let stroke: CGFloat = 1.75
    private static let turnPeriod: TimeInterval = 1.1
    private static let knockPeriod: TimeInterval = 2.4
    private static let knockLength: TimeInterval = 0.3
    private static let rippleLength: TimeInterval = 0.9

    var body: some View {
        Group {
            if let frozenAt {
                mark(time: frozenAt, burst: nil, moving: true)
            } else {
                TimelineView(schedule) { context in
                    mark(
                        time: context.date.timeIntervalSinceReferenceDate,
                        burst: finishedAt.map { context.date.timeIntervalSince($0) },
                        moving: moves)
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: isFinished) { _, finished in
            guard finished else {
                finishedAt = nil
                return
            }
            let stamp = Date()
            finishedAt = stamp
            Task {
                try? await Task.sleep(for: .seconds(1))
                if finishedAt == stamp { finishedAt = nil }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var isFinished: Bool { state == .finished }

    private var isNeedsInput: Bool {
        if case .needsInput = state { true } else { false }
    }

    /// Whether anything is in motion right now.
    private var moves: Bool {
        !reduceMotion && (state == .working || isNeedsInput || finishedAt != nil)
    }

    /// Whether Core Animation is turning the arc.
    private var spins: Bool {
        !reduceMotion && state == .working && frozenAt == nil
    }

    /// When the mark has to be redrawn: while it knocks, and while the finished ring goes
    /// out. The turning arc needs no redraws.
    private var schedule: FrameSchedule {
        if isNeedsInput, !reduceMotion {
            return FrameSchedule(
                interval: Self.frameInterval,
                pulse: .init(
                    anchor: Date(timeIntervalSinceReferenceDate: 0), period: Self.knockPeriod,
                    length: Self.knockWindow))
        }
        return FrameSchedule(
            interval: Self.frameInterval, paused: reduceMotion || finishedAt == nil)
    }

    private var color: Color {
        switch state {
        case .working: .white.opacity(0.9)
        case .needsInput: AgentPalette.alert
        case .finished: AgentPalette.mint
        case .running: .white.opacity(0.5)
        case .idle: .white.opacity(0.28)
        }
    }

    private var hasDot: Bool {
        isNeedsInput || state == .running
    }

    private func mark(time: TimeInterval, burst: TimeInterval?, moving: Bool) -> some View {
        let turn = moving && state == .working
            ? time.truncatingRemainder(dividingBy: Self.turnPeriod) / Self.turnPeriod * 360 : 0
        let beat = time.truncatingRemainder(dividingBy: Self.knockPeriod)
        let knocking = moving && isNeedsInput
        return ZStack {
            ripple(knocking ? Self.progress(beat, from: 0) : burst.flatMap { Self.progress($0, from: 0) })
            ripple(knocking ? Self.progress(beat, from: Self.knockLength) : nil)
            Circle()
                .trim(from: 0, to: state == .working ? 0.75 : 1)
                .stroke(color, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(turn - 90))
                .opacity(spins ? 0 : 1)
            if spins {
                SpinningArc(color: color, lineWidth: Self.stroke, period: Self.turnPeriod)
                    .transition(.opacity)
            }
            Circle()
                .fill(color)
                .frame(width: size * 0.29, height: size * 0.29)
                .scaleEffect(knocking ? Self.knockScale(beat) : 1)
                .opacity(hasDot ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: isFinished ? 1 : 0)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round))
                .padding(size * 0.29)
        }
        .padding(Self.stroke / 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state)
    }

    /// A ring that grows to twice the mark's size while it fades; nothing for nil.
    private func ripple(_ progress: Double?) -> some View {
        Circle()
            .stroke(color.opacity(0.6 * (1 - (progress ?? 1))), lineWidth: 1)
            .scaleEffect(1 + (progress ?? 0))
    }

    /// 0...1 through a ripple that started at `start` seconds into the beat; nil outside it.
    private static func progress(_ beat: TimeInterval, from start: TimeInterval) -> Double? {
        let value = (beat - start) / rippleLength
        return value >= 0 && value < 1 ? value : nil
    }

    /// Two knocks at the start of every beat, then rest.
    private static func knockScale(_ beat: TimeInterval) -> CGFloat {
        guard beat < 2 * knockLength else { return 1 }
        let local = beat.truncatingRemainder(dividingBy: knockLength) / knockLength
        return 1 + 0.35 * sin(.pi * local)
    }

    private var accessibilityText: String {
        switch state {
        case .working: "Working"
        case .needsInput: "Needs input"
        case .finished: "Finished"
        case .running: "Running"
        case .idle: "Idle"
        }
    }
}

/// A check mark filling its rect.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY * 0.92 + rect.minY * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}
```

- [ ] **Step 3: Write the pet**

`Symbiodock/Island/Agents/AgentPet.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// A tool's pet: a small field of fine vertical lines in the tool's colour, in which the
/// figure shows as the lines growing brighter and dimmer along their length, the way light
/// falls on a form. It moves with its session: while the session works a wave runs across
/// it from left to right, in depth (each line comes forward, a little larger and brighter,
/// and goes back); otherwise it stands still.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if frozenAt == nil, state == .working, !reduceMotion {
                // Smooth motion that never rests: Core Animation plays it, the app draws nothing.
                AgentPetWave(tool: tool, strength: strength, side: size)
                    .frame(width: size, height: size)
            } else {
                figure(waveAt: state == .working ? frozenAt : nil)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(tool.displayName)
    }

    /// A pet whose session is doing nothing steps back.
    private var strength: Double {
        switch state {
        case .working, .needsInput, .finished: 1
        case .running: 0.7
        case .idle: 0.45
        }
    }

    /// The pet drawn once. With `waveAt` each line is as far forward as the wave has it at
    /// that moment: larger about its centre and in full colour, the others a little
    /// weaker. The canvas reaches past
    /// the pet by the most a line can grow, so that nothing is cut.
    private func figure(waveAt time: TimeInterval?) -> some View {
        let art = AgentPetArt.art(for: tool, strength: strength)
        let lines = art.lines
        let grounds = art.grounds
        let margin = size * AgentPetMotion.waveGrowth / 2
        return Canvas { context, canvas in
            let side = canvas.width - 2 * margin
            let bar = side * AgentPetFigure.barWidth
            let inset = side * AgentPetArt.groundInset
            for (column, stretches) in lines.enumerated() {
                let x = margin + side * AgentPetFigure.pitch * CGFloat(column)
                let forward = time.map { AgentPetMotion.wave(column: column, at: $0) } ?? 0
                // Scaled about the line's own centre, and weaker while it waits for the crest.
                var line = context
                if time != nil {
                    line.opacity = AgentPetMotion.waveRest + (1 - AgentPetMotion.waveRest) * forward
                }
                let scale = 1 + AgentPetMotion.waveGrowth * forward
                let centre = CGPoint(x: x + bar / 2, y: margin + side / 2)
                line.translateBy(x: centre.x, y: centre.y)
                line.scaleBy(x: scale, y: scale)
                line.translateBy(x: -centre.x, y: -centre.y)
                let whole = CGRect(x: x, y: margin + inset, width: bar, height: side - 2 * inset)
                line.fill(Path(roundedRect: whole, cornerRadius: bar / 2), with: .color(grounds[column]))
                for stretch in stretches {
                    let rect = CGRect(
                        x: x, y: margin + side * stretch.top, width: bar,
                        height: max(side * (stretch.bottom - stretch.top), bar))
                        .intersection(whole)
                    guard !rect.isNull, rect.height > 0 else { continue }
                    line.fill(
                        Path(roundedRect: rect, cornerRadius: bar / 2),
                        with: .linearGradient(
                            stretch.gradient,
                            startPoint: CGPoint(x: x, y: margin + side * stretch.top),
                            endPoint: CGPoint(x: x, y: margin + side * stretch.bottom)))
                }
            }
        }
        .frame(width: size + 2 * margin, height: size + 2 * margin)
    }
}

/// The pets as they are drawn: for each line, the stretches where the figure is, each with
/// the gradient that carries its light and shade. Worked out once for each tool and
/// strength.
@MainActor
enum AgentPetArt {
    /// How far the ground of a line stops short of the pet's top and bottom, as a fraction
    /// of its side.
    static let groundInset = 0.025

    struct Stretch {
        let top: Double
        let bottom: Double
        let gradient: Gradient
    }

    private struct Key: Hashable {
        let tool: AgentTool
        /// Strength in hundredths.
        let strength: Int
    }

    /// Everything about a pet that does not depend on time.
    struct Art {
        let lines: [[Stretch]]
        let grounds: [Color]
    }

    private static var cache: [Key: Art] = [:]

    /// Where a point of the pet lies along its run of colours, which goes from the upper
    /// left (0) to the lower right (1): mostly across, partly down.
    private static func position(ofLine index: Int, down: Double = 0.5) -> Double {
        0.6 * Double(index) / Double(max(AgentPetFigure.lineCount - 1, 1)) + 0.4 * down
    }

    static func art(for tool: AgentTool, strength: Double) -> Art {
        let key = Key(tool: tool, strength: Int((strength * 100).rounded()))
        if let known = cache[key] { return known }
        let art = Art(lines: lines(for: tool, strength: strength), grounds: grounds(for: tool, strength: strength))
        cache[key] = art
        return art
    }

    /// The colour of each line where there is no figure.
    private static func grounds(for tool: AgentTool, strength: Double) -> [Color] {
        (0..<AgentPetFigure.lineCount).map {
            AgentPalette.tint(
                for: tool, strength: strength * AgentPetFigure.groundStrength, across: position(ofLine: $0))
        }
    }

    private static func lines(for tool: AgentTool, strength: Double) -> [[Stretch]] {
        let figure = AgentPetFigure.figure(for: tool)
        let lines = figure.lines.indices.map { index in
            figure.stretches(ofLine: index).map { stretch in
                let last = max(stretch.shades.count - 1, 1)
                let stops = stretch.shades.enumerated().map { position, shade in
                    Gradient.Stop(
                        // A part that glows keeps glowing however far the pet steps back.
                        color: AgentPalette.tint(
                            for: tool, strength: shade > 1 ? 1 + (shade - 1) * strength : strength * shade,
                            across: Self.position(
                                ofLine: index,
                                down: stretch.top + (stretch.bottom - stretch.top) * Double(position) / Double(last))),
                        location: CGFloat(position) / CGFloat(last))
                }
                return Stretch(top: stretch.top, bottom: stretch.bottom, gradient: Gradient(stops: stops))
            }
        }
        return lines
    }
}
```

The figures themselves come from `AgentPetGlyph` in the core package.

- [ ] **Step 4: Write the render harness**

`Symbiodock/App/DebugRender.swift`:

```swift
#if DEBUG
import AppKit
import SwiftUI
import SymbiodockCore

/// Draws the agent views to PNG files and quits, so their look can be checked without a
/// running agent. Debug builds only:
/// `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
@MainActor
enum DebugRender {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SYMBIODOCK_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(StatusMarkGallery(), size: CGSize(width: 560, height: 150), named: "status-marks", to: directory)
        write(PetGallery(), size: CGSize(width: 800, height: 380), named: "pets", to: directory)
        for (name, tab) in [("expanded-agents", IslandTab.agents), ("expanded-media", .media)] {
            let state = IslandState()
            DemoAgents.apply("1", to: state)
            state.setHovering(true)
            state.selectTab(tab)
            write(
                ExpandedPreview(state: state), size: CGSize(width: 580, height: 180),
                named: name, to: directory)
        }
        let empty = IslandState()
        empty.setHovering(true)
        empty.selectTab(.agents)
        write(
            ExpandedPreview(state: empty), size: CGSize(width: 580, height: 180),
            named: "expanded-agents-empty", to: directory)
        write(CollapsedGallery(), size: CGSize(width: 620, height: 480), named: "collapsed-faces", to: directory)
        exit(0)
    }

    /// Hosts the view in an off-screen window and saves what it draws.
    static func write(_ view: some View, size: CGSize, named name: String, to directory: URL) {
        let host = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
                .background(Color(white: 0.22)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // SwiftUI lays out and draws on the next turns of the run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

/// Every look of the status mark, large and at its real size.
private struct StatusMarkGallery: View {
    private static let states: [(String, AgentRowState, TimeInterval)] = [
        ("working", .working, 0.2),
        ("knock", .needsInput(prompt: nil), 0.15),
        ("ripple", .needsInput(prompt: nil), 0.7),
        ("finished", .finished, 0),
        ("running", .running, 0),
        ("idle", .idle, 0),
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                ForEach(Self.states, id: \.0) { name, state, time in
                    VStack(spacing: 8) {
                        AgentStatusMark(state: state, size: 42, frozenAt: time)
                            .frame(width: 60, height: 60)
                        AgentStatusMark(state: state, frozenAt: time)
                        Text(name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(12)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Every pet: large, at the size of a row, at the size of a wing, and in each state.
private struct PetGallery: View {
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ForEach(AgentTool.allCases, id: \.self) { tool in
                    VStack(spacing: 10) {
                        AgentPet(tool: tool, size: 84, frozenAt: 0)
                        HStack(spacing: 8) {
                            AgentPet(tool: tool, size: 36, frozenAt: 0)
                            AgentPet(tool: tool, size: 24, frozenAt: 0)
                        }
                        caption(tool.displayName)
                    }
                    .frame(width: 92)
                }
            }
            HStack(spacing: 18) {
                caption("working").frame(width: 44)
                ForEach([0.3, 0.65, 1.0], id: \.self) { time in
                    AgentPet(tool: .claudeCode, state: .working, size: 48, frozenAt: time)
                    AgentPet(tool: .codex, state: .working, size: 48, frozenAt: time)
                }
            }
            HStack(spacing: 18) {
                caption("states").frame(width: 44)
                AgentPet(tool: .claudeCode, state: .needsInput(prompt: nil), size: 48, frozenAt: 0.15)
                AgentPet(tool: .claudeCode, state: .finished, size: 48, frozenAt: 0)
                AgentPet(tool: .claudeCode, state: .running, size: 48, frozenAt: 0)
                AgentPet(tool: .claudeCode, state: .idle, size: 48, frozenAt: 0)
            }
        }
        .padding(18)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The open island as it is at the notch: 540 × 134, with a 200 × 32 camera housing.
private struct ExpandedPreview: View {
    let state: IslandState

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        ExpandedIsland(
            state: state,
            metrics: ExpandedHeaderMetrics(height: 32, leading: 170, gap: 200, trailing: 170),
            onCommand: { _ in }, onOpenSession: { _ in })
            .frame(width: 540, height: 134)
            .background(.black, in: shape)
            .clipShape(shape)
    }
}

/// The collapsed faces with their rim light: at the notch, as a capsule, as a strip.
private struct CollapsedGallery: View {
    private let now = Date()

    /// `AgentRow` has no public initialiser; a board produces the row for the wanted state.
    private func row(_ state: AgentRowState, _ tool: AgentTool = .claudeCode) -> AgentRow {
        func session(_ activity: AgentActivity) -> AgentSession {
            AgentSession(
                id: "x", tool: tool, title: "fix-login-flow", projectPath: nil,
                activity: activity, since: now, pid: nil)
        }
        var board = AgentSessionBoard()
        switch state {
        case .needsInput(let prompt): board.update([session(.needsInput(prompt: prompt))])
        case .working: board.update([session(.working)])
        case .running: board.update([session(.running)])
        case .idle: board.update([session(.idle)])
        case .finished:
            board.update([session(.working)])
            board.update([session(.idle)])
        }
        return board.rows[0]
    }

    private func notch(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: .notch, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: radii.bottomLeading, bottomTrailingRadius: radii.bottomTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentNotchFace(row: row(state), notchWidth: 200) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii, dockedEdges: [.top], isVertical: false,
                    frozenAt: time)
            }
            .frame(width: 272, height: 32)
            .clipShape(shape)
    }

    private func capsule(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let anchor = IslandAnchor.edge(.bottom, fraction: 0.5)
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentFloatingFace(row: row(state, .codex)) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii,
                    dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: false,
                    frozenAt: time)
            }
            .frame(width: 200, height: 36)
            .clipShape(shape)
    }

    private func strip(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let anchor = IslandAnchor.edge(.right, fraction: 0.5)
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentSideFace(row: row(state)) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii,
                    dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: true,
                    frozenAt: time)
            }
            .frame(width: 36, height: 170)
            .clipShape(shape)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                notch(.working, .none, at: 0)
                notch(.needsInput(prompt: nil), .needsInput, at: 0.45)
                notch(.needsInput(prompt: nil), .needsInput, at: 1.4)
                notch(.finished, .finished, at: 0.45)
                notch(.finished, .finished, at: 2)
                capsule(.needsInput(prompt: nil), .needsInput, at: 0.45)
                capsule(.finished, .finished, at: 2)
                AgentFloatingFace(row: nil)
                    .frame(width: 200, height: 36)
                    .background(.black, in: Capsule())
            }
            strip(.needsInput(prompt: nil), .needsInput, at: 0.45)
            strip(.finished, .finished, at: 2)
            strip(.working, .none, at: 0)
        }
        .padding(16)
    }
}
#endif
```

In `AppDelegate.applicationDidFinishLaunching`, as the very first lines:

```swift
        #if DEBUG
        DebugRender.runIfRequested()
        #endif
```

- [ ] **Step 5: Build, render and look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock; ls -l build/render
```

Expected: `** BUILD SUCCEEDED **`, the process exits by itself, `build/render/status-marks.png` and `build/render/pets.png` exist.

Open `status-marks.png` with the Read tool and check, one by one: the working mark is an open arc; the needs-input mark is a red ring with a centre dot, and its two frames differ (a bigger dot in `knock`, an outer ring in `ripple`); finished is a mint ring with a check mark inside it, not touching the ring; running is a dim ring with a dot; idle is a dimmer ring. If a shape is off (the check mark crooked, clipped, or outside the ring), fix the numbers and render again. If a picture is empty, the capture ran before SwiftUI drew: raise the run-loop wait, or call `window.displayIfNeeded()` before capturing.

Open `pets.png` with the Read tool. This is the design step; do it properly:

- Every pet is a square field of fine, evenly spaced vertical lines in its tool's colour. Where there is no figure the lines are faint; the figure shows as the lines growing brighter and dimmer along their length.
- Each figure reads as a lit form at 84 pt: Claude Code as a plump creature on two small feet, a rounded star with two small upright eyes; Codex as a plump cloud of round lobes, blue on the left and violet on the right, with `>_` glowing white on its front; Gemini as a faceted four-pointed star with a small one behind; Cursor as a cube whose three faces have three tones; OpenCode as a terminal window with a sunken screen and `>_`, and a dimmer window behind; Aider as an `A` of three tubes; Copilot as a round head with sunken goggles and two eyes.
- Each is still recognisable at 24 pt, and no two can be mistaken for each other.
- The colours are strong, not washed out: the lit parts of a figure show the tool's colour at or near full strength.
- In the `working` row the ends of the lines differ only slightly between the three frames: the pet stirs, it does not dance. In the `states` row the hopping pet sits a little higher than its neighbours, and running and idle are dimmer.

Where a figure falls short, change its relief in `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetRelief.swift`, run `swift test --package-path Packages/SymbiodockCore --filter AgentPetFigureTests`, build and render again. The lighting (how strong the shading is, how faint the ground lines are) is in `AgentPetFigure.swift`.

- [ ] **Step 6: Commit**

```bash
git add Symbiodock Packages docs/superpowers/plans
git commit -m "feat: draw the agent status mark and the pets"
git push origin main
```

---

### Task 2: Tabs in the expanded island and the Agents tab

**Files:**
- Create: `Symbiodock/Window/TabOrderStore.swift`
- Create: `Symbiodock/Island/TabStrip.swift`
- Create: `Symbiodock/Island/ExpandedIsland.swift`
- Create: `Symbiodock/Island/Agents/AgentsContent.swift`
- Create: `Symbiodock/Agents/DemoAgents.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Window/OverlayController.swift`
- Modify: `Symbiodock/App/IslandMenu.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`
- Modify: `Symbiodock/App/DebugRender.swift`

**Interfaces:**
- Consumes: core `IslandState` (`board`, `tabOrder`, `selectedTab`, `selectTab(_:)`, `setTabOrder(_:)`, `setAgentSessions(_:)`), `TabOrder`, `AgentRow`, `AgentLabels`; `AgentStatusMark`, `AgentPet`, `AgentPalette` (Task 1).
- Produces:
  - `TabOrderStore.load() -> [IslandTab]`, `TabOrderStore.save(_:)`.
  - `TabStrip(order:selected:attention:onSelect:)`, `IslandTab.symbol`, `IslandTab.title`.
  - `ExpandedHeaderMetrics(height:leading:gap:trailing:)`, `ExpandedIsland(state:metrics:onCommand:onOpenSession:)`, `ExpandedIsland.dockedBandHeight` (26).
  - `AgentsContent(rows:topInset:onOpen:)`.
  - `OverlayController.init(state:contextMenu:onCommand:onOpenSession:)`.
  - `IslandMenu.firstTab: () -> IslandTab`, `IslandMenu.onChooseFirstTab: ((IslandTab) -> Void)?`.
  - `DemoAgents.isRequested`, `DemoAgents.apply(to: IslandState)`.

- [ ] **Step 1: Store the tab order**

`Symbiodock/Window/TabOrderStore.swift`:

```swift
import Foundation
import SymbiodockCore

/// Remembers the order of the tabs across launches.
enum TabOrderStore {
    private static let key = "tabOrder"

    /// Anything missing or unreadable gives the default order.
    static func load() -> [IslandTab] {
        TabOrder.repaired(UserDefaults.standard.stringArray(forKey: key))
    }

    static func save(_ order: [IslandTab]) {
        UserDefaults.standard.set(TabOrder.encode(order), forKey: key)
    }
}
```

- [ ] **Step 2: Write the tab strip**

`Symbiodock/Island/TabStrip.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The tab buttons of the expanded island, in the user's order.
struct TabStrip: View {
    let order: [IslandTab]
    let selected: IslandTab
    let attention: AgentAttention
    let onSelect: (IslandTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(order, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    glyph(tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(pipText(for: tab))
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
    }

    /// Whether the pip is showing on this tab's glyph: the agents want attention while
    /// another tab is looked at.
    private func showsPip(_ tab: IslandTab) -> Bool {
        tab == .agents && selected != .agents && attention != .none
    }

    /// What the pip says, for VoiceOver; empty while there is no pip.
    private func pipText(for tab: IslandTab) -> String {
        guard showsPip(tab) else { return "" }
        return attention == .needsInput ? "Needs input" : "Finished"
    }

    private func glyph(_ tab: IslandTab) -> some View {
        VStack(spacing: 2) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    // The agents want attention while another tab is looked at.
                    if showsPip(tab) {
                        Circle()
                            .fill(attention == .needsInput ? AgentPalette.alert : AgentPalette.mint)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -3)
                    }
                }
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .opacity(tab == selected ? 1 : 0)
        }
        .foregroundStyle(.white.opacity(tab == selected ? 1 : 0.4))
        .frame(width: 28, height: 22)
        .contentShape(Rectangle())
    }
}

extension IslandTab {
    var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .media: "music.note"
        }
    }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .media: "Media"
        }
    }
}
```

- [ ] **Step 3: Write the Agents tab**

`Symbiodock/Island/Agents/AgentsContent.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The Agents tab: the sessions one under the other, two at a time, or an idle message.
struct AgentsContent: View {
    let rows: [AgentRow]
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat
    let onOpen: (AgentSession) -> Void

    /// How many sessions are visible at once; the rest are reached by scrolling.
    private static let visibleRows = 2
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        Group {
            if rows.isEmpty {
                idle
            } else {
                list
            }
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("No agents running")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// As tall as the rows it shows, so one or two rows sit centred below the header.
    private var viewportHeight: CGFloat {
        let shown = CGFloat(min(rows.count, Self.visibleRows))
        return shown * AgentRowView.height + (shown - 1) * Self.rowSpacing
    }

    private var list: some View {
        // The labels count minutes; they are redrawn on their own now and then.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(rows) { row in
                        AgentRowView(row: row, now: context.date, onOpen: onOpen)
                    }
                }
                .scrollTargetLayout()
            }
            // The list comes to rest on a row, never between two.
            .scrollTargetBehavior(.viewAligned)
            .frame(height: viewportHeight)
            .mask {
                // Fading out at the lower edge says that the list goes on.
                if rows.count > Self.visibleRows {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.84),
                            .init(color: .black.opacity(0.25), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct AgentRowView: View {
    static let height: CGFloat = 46

    let row: AgentRow
    let now: Date
    let onOpen: (AgentSession) -> Void

    var body: some View {
        if row.session.hostAppPID != nil {
            Button {
                onOpen(row.session)
            } label: {
                content
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Brings its app to the front")
        } else {
            content
        }
    }

    private var prompt: String? {
        if case .needsInput(let prompt) = row.state { prompt } else { nil }
    }

    private var needsInput: Bool {
        if case .needsInput = row.state { true } else { false }
    }

    private var labelColor: Color {
        switch row.state {
        case .needsInput: AgentPalette.alert
        case .finished: AgentPalette.mint
        case .working, .running, .idle: .white.opacity(0.6)
        }
    }

    /// The tool and the project folder: "Claude Code · storefront".
    private var origin: String {
        guard let project = row.session.projectName, project != row.session.title else {
            return row.session.tool.displayName
        }
        return "\(row.session.tool.displayName) · \(project)"
    }

    private var content: some View {
        HStack(spacing: 10) {
            AgentPet(tool: row.session.tool, state: row.state, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(row.state == .idle ? 0.6 : 1))
                    .lineLimit(1)
                Text(prompt ?? origin)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(prompt == nil ? 0.5 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(AgentLabels.status(row.state, since: row.session.since, now: now))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize()
            AgentStatusMark(state: row.state)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if needsInput {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AgentPalette.alert.opacity(0.12))
            }
        }
        .overlay(alignment: .leading) {
            if needsInput {
                Capsule().fill(AgentPalette.alert).frame(width: 2).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A row dims while it is pressed, so a click is felt.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
```

- [ ] **Step 4: Write the expanded island**

`Symbiodock/Island/ExpandedIsland.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// Where the header's parts go. At the notch the camera housing sits in the middle of the
/// band, so the tab strip is left of it and the summary right of it.
struct ExpandedHeaderMetrics: Equatable {
    var height: CGFloat
    var leading: CGFloat
    /// Width hidden by the camera housing; 0 away from the notch.
    var gap: CGFloat
    var trailing: CGFloat
}

/// The open island: a header band with the tabs, and the selected tab below it.
struct ExpandedIsland: View {
    /// Height of the header band where there is no notch to give it one.
    static let dockedBandHeight: CGFloat = 26

    let state: IslandState
    let metrics: ExpandedHeaderMetrics
    let onCommand: (PlaybackCommand) -> Void
    let onOpenSession: (AgentSession) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch state.selectedTab {
                case .media:
                    ExpandedContent(
                        info: state.nowPlaying, topInset: metrics.height, onCommand: onCommand)
                case .agents:
                    AgentsContent(
                        rows: state.board.rows, topInset: metrics.height, onOpen: onOpenSession)
                }
            }
            .transition(.opacity)
            header
        }
        .animation(.easeOut(duration: 0.15), value: state.selectedTab)
    }

    private var header: some View {
        HStack(spacing: 0) {
            TabStrip(
                order: state.tabOrder, selected: state.selectedTab,
                attention: state.board.attention
            ) { tab in
                state.selectTab(tab)
            }
            .padding(.leading, 14)
            .frame(width: metrics.leading, alignment: .leading)

            Color.clear.frame(width: metrics.gap)

            // The summary can be absent; the column keeps its width regardless.
            Color.clear
                .frame(width: metrics.trailing)
                .overlay(alignment: .trailing) {
                    summary.padding(.trailing, 14)
                }
        }
        .frame(height: metrics.height)
    }

    @ViewBuilder
    private var summary: some View {
        if state.selectedTab == .agents,
           let text = AgentLabels.summary(
               needsInput: state.board.needsInputCount, working: state.board.workingCount) {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
```

- [ ] **Step 5: Use it in `IslandView`**

In `Symbiodock/Island/IslandView.swift`:

1. Add a stored property after `onCommand`:

```swift
    let onOpenSession: (AgentSession) -> Void
```

2. In `resting`, change `.overlay { content(atNotch: atNotch) }` to `.overlay { content(atNotch: atNotch, frame: frame) }`.

3. Change the signature `private func content(atNotch: Bool) -> some View` to `private func content(atNotch: Bool, frame: CGRect) -> some View`, and replace its `.expanded` case with:

```swift
        case .expanded:
            ExpandedIsland(
                state: state, metrics: headerMetrics(atNotch: atNotch, frame: frame),
                onCommand: onCommand, onOpenSession: onOpenSession)
                .transition(.opacity)
```

4. Add below `content`:

```swift
    /// At the notch the header shares its band with the camera housing; elsewhere it has
    /// a band of its own, split down the middle.
    private func headerMetrics(atNotch: Bool, frame: CGRect) -> ExpandedHeaderMetrics {
        guard atNotch else {
            return ExpandedHeaderMetrics(
                height: ExpandedIsland.dockedBandHeight,
                leading: frame.width / 2, gap: 0, trailing: frame.width / 2)
        }
        let notch = geometry.notch
        return ExpandedHeaderMetrics(
            height: notch.height,
            leading: max(notch.minX - frame.minX, 0),
            gap: notch.width,
            trailing: max(frame.maxX - notch.maxX, 0))
    }
```

- [ ] **Step 6: Pass the new callback through `OverlayController`**

In `Symbiodock/Window/OverlayController.swift`:

1. Add `private let onOpenSession: (AgentSession) -> Void` next to `onCommand`.
2. Change the initialiser to:

```swift
    init(
        state: IslandState, contextMenu: NSMenu,
        onCommand: @escaping (PlaybackCommand) -> Void,
        onOpenSession: @escaping (AgentSession) -> Void
    ) {
        self.state = state
        self.contextMenu = contextMenu
        self.onCommand = onCommand
        self.onOpenSession = onOpenSession
        session.onCatch = {
            Self.dragLog.notice("strands caught a surface")
            Self.haptic(.alignment)
        }
    }
```

3. In `rebuildPanel()`, build the view with the new argument:

```swift
        let hostingView = IslandHostingView(rootView: IslandView(
            state: state, geometry: geometry, session: session, onCommand: onCommand,
            onOpenSession: onOpenSession))
```

- [ ] **Step 7: Add `First tab` to the menu**

In `Symbiodock/App/IslandMenu.swift`:

1. Add `import SymbiodockCore` below `import AppKit`.
2. Add properties next to `returnToNotchItem`:

```swift
    private let firstTabItem = NSMenuItem(title: "First tab", action: nil, keyEquivalent: "")
    private var tabItems: [(tab: IslandTab, item: NSMenuItem)] = []

    /// Set by the app: the tab that is first now.
    var firstTab: () -> IslandTab = { TabOrder.default[0] }
    /// Set by the app: the user chose a tab to be first.
    var onChooseFirstTab: ((IslandTab) -> Void)?
```

3. In `init`, after `menu.addItem(returnToNotchItem)`:

```swift
        let tabMenu = NSMenu()
        for tab in TabOrder.default {
            let item = NSMenuItem(
                title: tab.title, action: #selector(chooseFirstTab(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            tabMenu.addItem(item)
            tabItems.append((tab, item))
        }
        firstTabItem.submenu = tabMenu
        menu.addItem(firstTabItem)
```

4. In `menuNeedsUpdate(_:)`, add:

```swift
        let first = firstTab()
        for (tab, item) in tabItems { item.state = tab == first ? .on : .off }
```

5. Add the action:

```swift
    @objc private func chooseFirstTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = IslandTab(rawValue: raw)
        else { return }
        onChooseFirstTab?(tab)
    }
```

`IslandTab.title` comes from `TabStrip.swift`.

- [ ] **Step 8: Add the demo sessions**

`Symbiodock/Agents/DemoAgents.swift`:

```swift
#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed set of sessions for looking at the Agents tab without running an agent:
/// `open --env SYMBIODOCK_DEMO_AGENTS=1 build/Build/Products/Debug/Symbiodock.app`.
/// The value picks the set: `1` all states, `working`, `finished`, `quiet`.
@MainActor
enum DemoAgents {
    static var requested: String? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_AGENTS"]
    }

    static func apply(_ set: String, to state: IslandState, now: Date = Date()) {
        func session(
            _ id: String, _ tool: AgentTool, _ title: String, _ project: String,
            _ activity: AgentActivity, minutes: Double
        ) -> AgentSession {
            AgentSession(
                id: id, tool: tool, title: title, projectPath: "/Users/demo/\(project)",
                activity: activity, since: now.addingTimeInterval(-minutes * 60), pid: nil,
                hostAppPID: ProcessInfo.processInfo.processIdentifier)
        }
        let ask = session(
            "a", .claudeCode, "fix-login-flow", "storefront",
            .needsInput(prompt: "Which of the two migrations should run first?"), minutes: 1)
        let work = session("b", .codex, "Tune the monitor", "dotfiles", .working, minutes: 2)
        let done = session("c", .claudeCode, "api-refactor", "backend", .idle, minutes: 0.5)
        let open = session("d", .geminiCLI, "notes", "notes", .running, minutes: 40)
        let idle = session("e", .aider, "parser", "parser", .idle, minutes: 12)

        switch set {
        case "working":
            state.setAgentSessions([work, idle])
        case "finished":
            state.setAgentSessions([session("c", .claudeCode, "api-refactor", "backend", .working, minutes: 3)])
            state.setAgentSessions([done])
        case "quiet":
            state.setAgentSessions([open, idle])
        default:
            // `c` is seen working first, so that it shows as finished.
            state.setAgentSessions([
                ask, work, session("c", .claudeCode, "api-refactor", "backend", .working, minutes: 3),
                open, idle,
            ])
            state.setAgentSessions([ask, work, done, open, idle])
        }
    }
}
#endif
```

- [ ] **Step 9: Wire it in `AppDelegate`**

In `Symbiodock/App/AppDelegate.swift`, replace the creation of the overlay controller and what follows up to (not including) `let nowPlaying = …` with:

```swift
        state.setTabOrder(TabOrderStore.load())

        let overlayController = OverlayController(
            state: state, contextMenu: islandMenu.menu,
            onCommand: { [weak self] command in
                self?.nowPlaying?.send(command)
            },
            onOpenSession: { _ in })
        overlayController.start()
        self.overlayController = overlayController
        islandMenu.onReturnToNotch = { [weak overlayController] in overlayController?.returnToNotch() }
        islandMenu.canReturnToNotch = { [weak self] in self.map { $0.state.anchor != .notch } ?? false }
        islandMenu.firstTab = { [weak self] in self?.state.tabOrder.first ?? TabOrder.default[0] }
        islandMenu.onChooseFirstTab = { [weak self] tab in
            guard let self else { return }
            let order = TabOrder.moving(tab, toFrontOf: self.state.tabOrder)
            self.state.setTabOrder(order)
            TabOrderStore.save(order)
            // The collapsed face, and with it the hit rect, may have changed.
            self.overlayController?.refreshPointer()
        }

        #if DEBUG
        if let demo = DemoAgents.requested {
            DemoAgents.apply(demo, to: state)
            overlayController.refreshPointer()
        }
        #endif
```

- [ ] **Step 10: Render the Agents tab**

In `Symbiodock/App/DebugRender.swift`, in `runIfRequested()` before `exit(0)`:

```swift
        for (name, tab) in [("expanded-agents", IslandTab.agents), ("expanded-media", .media)] {
            let state = IslandState()
            DemoAgents.apply("1", to: state)
            state.setHovering(true)
            state.selectTab(tab)
            write(
                ExpandedPreview(state: state), size: CGSize(width: 580, height: 180),
                named: name, to: directory)
        }
        let empty = IslandState()
        empty.setHovering(true)
        empty.selectTab(.agents)
        write(
            ExpandedPreview(state: empty), size: CGSize(width: 580, height: 180),
            named: "expanded-agents-empty", to: directory)
```

and at the end of the file, inside the `#if DEBUG`:

```swift
/// The open island as it is at the notch: 540 × 134, with a 200 × 32 camera housing.
private struct ExpandedPreview: View {
    let state: IslandState

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        ExpandedIsland(
            state: state,
            metrics: ExpandedHeaderMetrics(height: 32, leading: 170, gap: 200, trailing: 170),
            onCommand: { _ in }, onOpenSession: { _ in })
            .frame(width: 540, height: 134)
            .background(.black, in: shape)
            .clipShape(shape)
    }
}
```

Note: selecting `.media` after the Agents tab clears the finished mark, which is the designed behaviour; the media render therefore shows no pip for it but still shows the red pip for the session that needs input.

- [ ] **Step 11: Build, render and look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock; ls build/render
```

Open `expanded-agents.png`, `expanded-media.png` and `expanded-agents-empty.png` with the Read tool and check:

- Two tab glyphs at the top left; the selected one is bright with a dot under it.
- `expanded-agents`: exactly two rows are visible, the one that needs input and the working one, each with its tool's pet at the left in the tool's colour, a title, a second line, a label and the status mark. The first row has the red bar and tint and shows its question as the second line; the second reads `Codex · dotfiles`. Labels read `Needs input` and `Working 2m`. The rows sit centred between the header band and the island's lower edge, the second fading slightly at its lower edge. Nothing overlaps or is cut off horizontally. `1 needs input · 1 working` is at the top right.
- `expanded-media`: `Nothing playing`, and a red pip on the Agents glyph.
- `expanded-agents-empty`: the sparkles glyph and `No agents running`.

The other three sessions are below the fold (the list scrolls). If a `ScrollView` draws nothing in the render, check the live app instead (next step) before changing anything.

- [ ] **Step 12: Check it in the running app**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=1 build/Build/Products/Debug/Symbiodock.app; sleep 2; swift scripts/list-windows.swift
```

Expected: one window line for Symbiodock. Then `pkill -x Symbiodock`.

- [ ] **Step 13: Commit**

```bash
git add Symbiodock docs/superpowers/plans
git commit -m "feat: add tabs and the Agents tab to the open island"
git push origin main
```

---

### Task 3: Collapsed faces and the rim light

**Files:**
- Create: `Symbiodock/Island/Agents/AgentFaces.swift`
- Create: `Symbiodock/Island/RimLight.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Island/CollapsedContent.swift`
- Modify: `Symbiodock/Island/FloatingCollapsedContent.swift`
- Modify: `Symbiodock/Island/SideCollapsedContent.swift`
- Modify: `Symbiodock/App/DebugRender.swift`

**Interfaces:**
- Consumes: `IslandState.face`, `IslandState.board` (`lead`, `attention`), `IslandLayout.dockedEdges(anchor:)`, `IslandCornerRadii`; `AgentStatusMark`, `AgentPet`, `AgentPalette`.
- Produces: `AgentNotchFace(row:notchWidth:)`, `AgentFloatingFace(row:)`, `AgentSideFace(row:)` (the last two take `AgentRow?`; nil shows the idle text); `RimLight(attention:radii:dockedEdges:isVertical:frozenAt:)`; an `attention: AgentRowState?` parameter on `CollapsedContent`, `FloatingCollapsedContent` and `SideCollapsedContent`; `RotatedLine` becomes internal.

- [ ] **Step 1: Let the media faces carry the status mark**

`Symbiodock/Island/CollapsedContent.swift` becomes:

```swift
import SwiftUI
import SymbiodockCore

/// Artwork in the left wing, level bars in the right wing, nothing over the notch itself.
/// While an agent wants attention, its status mark takes the place of the level bars.
struct CollapsedContent: View {
    let info: NowPlayingInfo
    let notchWidth: CGFloat
    var attention: AgentRowState?

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(data: info.artworkData, size: 20)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            Group {
                if let attention {
                    AgentStatusMark(state: attention)
                } else {
                    LevelBars(isPlaying: info.isPlaying)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
```

In `FloatingCollapsedContent.swift` add `var attention: AgentRowState?` after `let info`, and replace the two lines

```swift
                LevelBars(isPlaying: info.isPlaying)
                    .opacity(info.isPlaying ? 1 : 0.4)
```

with

```swift
                if let attention {
                    AgentStatusMark(state: attention)
                } else {
                    LevelBars(isPlaying: info.isPlaying)
                        .opacity(info.isPlaying ? 1 : 0.4)
                }
```

In `SideCollapsedContent.swift` do the same (add the property, replace the same two lines), and change `private struct RotatedLine` to `struct RotatedLine` so the agent strip can use it. Read the file first; keep everything else as it is.

- [ ] **Step 2: Write the agent faces**

`Symbiodock/Island/Agents/AgentFaces.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The collapsed island speaking for the agents at the notch: the lead session's pet in
/// the left wing, its state in the right wing.
struct AgentNotchFace: View {
    let row: AgentRow
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            AgentPet(tool: row.session.tool, state: row.state, size: 24)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            AgentStatusMark(state: row.state)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentFaceLabel.text(for: row))
    }
}

/// The same in the capsule of an island docked at an edge or corner. Without a session to
/// speak for it says what the tab is, because a docked island never hides.
struct AgentFloatingFace: View {
    let row: AgentRow?

    var body: some View {
        HStack(spacing: 8) {
            if let row {
                AgentPet(tool: row.session.tool, state: row.state, size: 24)
                Text(row.session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                AgentStatusMark(state: row.state)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("No agents running")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, row == nil ? 14 : 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentFaceLabel.text(for: row))
    }
}

/// The same in the vertical strip of an island docked on the left or right edge.
struct AgentSideFace: View {
    let row: AgentRow?

    var body: some View {
        VStack(spacing: 8) {
            if let row {
                AgentPet(tool: row.session.tool, state: row.state, size: 24)
                RotatedLine(text: row.session.title)
                    .foregroundStyle(.white)
                AgentStatusMark(state: row.state)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: 18)
                RotatedLine(text: "No agents running")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentFaceLabel.text(for: row))
    }
}

/// What VoiceOver says for a face: the tool, the session and its state.
private enum AgentFaceLabel {
    static func text(for row: AgentRow?) -> String {
        guard let row else { return "No agents running" }
        let state: String = switch row.state {
        case .needsInput: "Needs input"
        case .working: "Working"
        case .finished: "Finished"
        case .running: "Running"
        case .idle: "Idle"
        }
        return "\(row.session.tool.displayName), \(row.session.title), \(state)"
    }
}
```

Before writing `AgentSideFace`, read `SideCollapsedContent.swift` and give the strip the same paddings and spacing that file uses for its own `VStack`, so both faces sit alike.

- [ ] **Step 3: Write the rim light**

`Symbiodock/Island/RimLight.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// A light along the collapsed island's rim while an agent wants attention. It is drawn
/// inside the island's outline, so the island's frame and hit area stay what they are,
/// and it leaves out the edges that lie against the screen.
struct RimLight: View {
    let attention: AgentAttention
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>
    /// The island is a vertical strip: the highlight travels down instead of across.
    let isVertical: Bool
    /// Draws the light this many seconds after it appeared and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    /// The finished light has made its one pass and is now still.
    @State private var settled = false

    private static let breathPeriod: TimeInterval = 1.8
    private static let passPeriod: TimeInterval = 3.6
    private static let passLength: TimeInterval = 0.9
    /// The highlight crosses the island in under a second and needs more while it does.
    private static let passInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        Group {
            if attention == .none {
                EmptyView()
            } else if let frozenAt {
                light(elapsed: frozenAt, moving: true)
            } else if breathes {
                // The breath never rests, so Core Animation plays it; the highlight crosses
                // the rim in under a second and is redrawn only while it does.
                ZStack {
                    Breathing(dimmest: Float(Self.dimmestLevel / Self.brightestLevel), period: Self.breathPeriod) {
                        glow(color: AgentPalette.alert, level: Self.brightestLevel)
                    }
                    TimelineView(passSchedule) { context in
                        highlightLayer(
                            pass: Self.pass(
                                elapsed: context.date.timeIntervalSince(appeared), repeating: true))
                    }
                }
            } else {
                TimelineView(FrameSchedule(interval: Self.passInterval, paused: !moves)) { context in
                    light(elapsed: context.date.timeIntervalSince(appeared), moving: moves)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { restart() }
        .onChange(of: attention) { restart() }
    }

    private static let dimmestLevel = 0.35
    private static let brightestLevel = 0.9

    /// Whether the needs-input light is breathing.
    private var breathes: Bool { attention == .needsInput && !reduceMotion }

    /// The highlight's passes, one every `passPeriod`.
    private var passSchedule: FrameSchedule {
        FrameSchedule(
            interval: Self.passInterval,
            pulse: .init(anchor: appeared, period: Self.passPeriod, length: Self.passLength + 0.05))
    }

    private var moves: Bool {
        !reduceMotion && (attention == .needsInput || (attention == .finished && !settled))
    }

    private func restart() {
        let stamp = Date()
        appeared = stamp
        settled = false
        guard attention == .finished else { return }
        Task {
            try? await Task.sleep(for: .seconds(Self.passLength + 0.1))
            if appeared == stamp { settled = true }
        }
    }

    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
    }

    /// How far the highlight has crossed, 0...1; nil while it is not on its way.
    private static func pass(elapsed: TimeInterval, repeating: Bool) -> Double? {
        let beat = repeating ? elapsed.truncatingRemainder(dividingBy: passPeriod) : elapsed
        return beat >= 0 && beat < passLength ? beat / passLength : nil
    }

    /// The whole light at one moment: the glow, and the highlight if it is on its way.
    private func light(elapsed: TimeInterval, moving: Bool) -> some View {
        let color = attention == .needsInput ? AgentPalette.alert : AgentPalette.mint
        let level: Double
        let pass: Double?
        switch attention {
        case .needsInput:
            // Breathes between 35 % and 90 %.
            level = moving
                ? 0.625 + 0.275 * sin(2 * .pi * elapsed / Self.breathPeriod) : 0.8
            pass = moving ? Self.pass(elapsed: elapsed, repeating: true) : nil
        case .finished, .none:
            level = 0.5
            pass = moving ? Self.pass(elapsed: elapsed, repeating: false) : nil
        }
        return ZStack {
            glow(color: color, level: level)
            highlightLayer(pass: pass)
        }
    }

    /// A glow without a blur: wider strokes under the line, each fainter, which add up to
    /// a soft falloff. Only the first reaches no further in than the edges that are cut.
    private func glow(color: Color, level: Double) -> some View {
        ZStack {
            outline.strokeBorder(color.opacity(level * 0.10), lineWidth: 7)
            outline.strokeBorder(color.opacity(level * 0.16), lineWidth: 5)
            outline.strokeBorder(color.opacity(level * 0.30), lineWidth: 3)
            outline.strokeBorder(color.opacity(level), lineWidth: 1.5)
        }
        .mask { Rectangle().padding(edgeInsets) }
    }

    @ViewBuilder
    private func highlightLayer(pass: Double?) -> some View {
        if let pass {
            outline.strokeBorder(highlight, lineWidth: 1.5)
                .mask { band(at: pass) }
                .mask { Rectangle().padding(edgeInsets) }
        }
    }

    /// `AgentPalette.mint` a third of the way to white.
    private static let brightMint = Color(red: 154.0 / 255.0, green: 239.0 / 255.0, blue: 200.0 / 255.0)

    /// The travelling highlight: nearly white when input is needed, a brightened mint when
    /// the session has finished.
    private var highlight: Color {
        attention == .needsInput ? .white.opacity(0.85) : Self.brightMint
    }

    /// Hides the stroke on the edges that touch the screen: a notch has no line there.
    private var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: dockedEdges.contains(.top) ? 3 : 0,
            leading: dockedEdges.contains(.left) ? 3 : 0,
            bottom: dockedEdges.contains(.bottom) ? 3 : 0,
            trailing: dockedEdges.contains(.right) ? 3 : 0)
    }

    /// A soft band crossing the island along its long axis; `position` runs 0...1.
    private func band(at position: Double) -> some View {
        GeometryReader { proxy in
            let length = isVertical ? proxy.size.height : proxy.size.width
            let width = max(length * 0.35, 24)
            let offset = -width + position * (length + width)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white, .clear],
                        startPoint: isVertical ? .top : .leading,
                        endPoint: isVertical ? .bottom : .trailing))
                .frame(
                    width: isVertical ? proxy.size.width : width,
                    height: isVertical ? width : proxy.size.height)
                .offset(x: isVertical ? 0 : offset, y: isVertical ? offset : 0)
        }
    }
}
```

- [ ] **Step 4: Show the faces and the light in `IslandView`**

In `Symbiodock/Island/IslandView.swift`:

1. In `resting`, after `.overlay { content(atNotch: atNotch, frame: frame) }` add:

```swift
            .overlay {
                if state.phase == .collapsed {
                    RimLight(
                        attention: state.board.attention, radii: radii,
                        dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor),
                        isVertical: IslandLayout.isSideDocked(state.anchor))
                }
            }
```

2. Add `.animation(Self.spring, value: state.face)` next to the other `.animation` modifiers.

3. Replace the `case .collapsed, .stretching, .detached, .settling:` branch of `content` with:

```swift
        case .collapsed, .stretching, .detached, .settling:
            collapsedFace(atNotch: atNotch)
                .transition(.opacity)
```

4. Add:

```swift
    /// The collapsed island shows one face: the first tab's if it has one, else the other's.
    @ViewBuilder
    private func collapsedFace(atNotch: Bool) -> some View {
        let lead = state.board.lead
        // On the media face an agent that wants attention still gets its mark.
        let attention = state.board.attentionRow?.state
        // A docked island never hides: with no face it shows the paused track if there is
        // one, otherwise the first tab's idle text.
        let agentsSpeak = state.face == .agents
            || (state.face == .none && state.nowPlaying == nil && state.tabOrder.first == .agents)

        if atNotch {
            switch state.face {
            case .agents:
                if let lead {
                    AgentNotchFace(row: lead, notchWidth: geometry.notch.width)
                }
            case .media:
                if let info = state.nowPlaying {
                    CollapsedContent(
                        info: info, notchWidth: geometry.notch.width, attention: attention)
                }
            case .none:
                EmptyView()
            }
        } else if IslandLayout.isSideDocked(state.anchor) {
            if agentsSpeak {
                AgentSideFace(row: state.board.spokesperson)
            } else {
                SideCollapsedContent(info: state.nowPlaying, attention: attention)
            }
        } else {
            if agentsSpeak {
                AgentFloatingFace(row: state.board.spokesperson)
            } else {
                FloatingCollapsedContent(info: state.nowPlaying, attention: attention)
            }
        }
    }
```

- [ ] **Step 5: Render the faces**

In `DebugRender.runIfRequested()` before `exit(0)`:

```swift
        write(CollapsedGallery(), size: CGSize(width: 620, height: 480), named: "collapsed-faces", to: directory)
```

and at the end of the file, inside the `#if DEBUG`:

```swift
/// The collapsed faces with their rim light: at the notch, as a capsule, as a strip.
private struct CollapsedGallery: View {
    private let now = Date()

    /// `AgentRow` has no public initialiser; a board produces the row for the wanted state.
    private func row(_ state: AgentRowState, _ tool: AgentTool = .claudeCode) -> AgentRow {
        func session(_ activity: AgentActivity) -> AgentSession {
            AgentSession(
                id: "x", tool: tool, title: "fix-login-flow", projectPath: nil,
                activity: activity, since: now, pid: nil)
        }
        var board = AgentSessionBoard()
        switch state {
        case .needsInput(let prompt): board.update([session(.needsInput(prompt: prompt))])
        case .working: board.update([session(.working)])
        case .running: board.update([session(.running)])
        case .idle: board.update([session(.idle)])
        case .finished:
            board.update([session(.working)])
            board.update([session(.idle)])
        }
        return board.rows[0]
    }

    private func notch(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: .notch, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: radii.bottomLeading, bottomTrailingRadius: radii.bottomTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentNotchFace(row: row(state), notchWidth: 200) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii, dockedEdges: [.top], isVertical: false,
                    frozenAt: time)
            }
            .frame(width: 272, height: 32)
            .clipShape(shape)
    }

    private func capsule(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let anchor = IslandAnchor.edge(.bottom, fraction: 0.5)
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentFloatingFace(row: row(state, .codex)) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii,
                    dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: false,
                    frozenAt: time)
            }
            .frame(width: 200, height: 36)
            .clipShape(shape)
    }

    private func strip(_ state: AgentRowState, _ attention: AgentAttention, at time: TimeInterval) -> some View {
        let anchor = IslandAnchor.edge(.right, fraction: 0.5)
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentSideFace(row: row(state)) }
            .overlay {
                RimLight(
                    attention: attention, radii: radii,
                    dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: true,
                    frozenAt: time)
            }
            .frame(width: 36, height: 170)
            .clipShape(shape)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                notch(.working, .none, at: 0)
                notch(.needsInput(prompt: nil), .needsInput, at: 0.45)
                notch(.needsInput(prompt: nil), .needsInput, at: 1.4)
                notch(.finished, .finished, at: 0.45)
                notch(.finished, .finished, at: 2)
                capsule(.needsInput(prompt: nil), .needsInput, at: 0.45)
                capsule(.finished, .finished, at: 2)
                AgentFloatingFace(row: nil)
                    .frame(width: 200, height: 36)
                    .background(.black, in: Capsule())
            }
            strip(.needsInput(prompt: nil), .needsInput, at: 0.45)
            strip(.finished, .finished, at: 2)
            strip(.working, .none, at: 0)
        }
        .padding(16)
    }
}
```

- [ ] **Step 6: Build, render and look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Open `build/render/collapsed-faces.png` with the Read tool and check:

- At the notch, the pet is centred in the left wing and the status mark in the right wing; nothing is drawn in the 200 pt middle. The pet is recognisable at this size.
- The rim light follows the island's outline on the free edges only: no line along the top of the notch island, none on the bottom edge of the capsule, none on the right edge of the strip.
- Needs input: a red line; in the frame at 0.45 s a brighter stretch is visible part of the way across (down, on the strip); at 1.4 s there is none.
- Finished: a mint line; a brighter stretch at 0.45 s, a plain line at 2 s.
- The working face has no rim light.
- Text in the strip runs along it and is not cut at the ends.

A blur that does not show in an off-screen capture is acceptable; a missing line is not. Fix and render again until every point holds.

- [ ] **Step 7: Check the running app in every demo set**

```bash
for set in 1 working finished quiet; do
  pkill -x Symbiodock; while pgrep -x Symbiodock >/dev/null; do sleep 0.1; done
  open --env SYMBIODOCK_DEMO_AGENTS=$set build/Build/Products/Debug/Symbiodock.app; sleep 2
  echo "$set: $(swift scripts/list-windows.swift)"
done
pkill -x Symbiodock
```

Expected: one window line per set, no crash (`pgrep` finds the app before it is killed). If `screencapture -x build/render/live.png` works without a permission dialog on this Mac, take one per set and look at the top of the screen; if it asks for permission, skip it and say so in the report.

- [ ] **Step 8: Commit**

```bash
git add Symbiodock docs/superpowers/plans
git commit -m "feat: show agents on the collapsed island with a rim light"
git push origin main
```

---

### Task 4: Reading files and processes, the coordinator, Claude Code

**Files:**
- Create: `Symbiodock/Agents/FileReading.swift`
- Create: `Symbiodock/Agents/ProcessScanner.swift`
- Create: `Symbiodock/Agents/ClaudeCodeProvider.swift`
- Create: `Symbiodock/Agents/AgentProviders.swift`
- Create: `Symbiodock/Agents/AgentSessionCoordinator.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: core `ClaudeSessionParser`, `ClaudeTranscriptPromptReader`, `ProcessSnapshot`, `AgentProcessMatcher`, `AgentScanContext`, `AgentSessionProvider`.
- Produces:
  - `FileReading.whole(_ url: URL, maxBytes: Int) -> Data?`, `.head(of:maxBytes:) -> Data?`, `.tail(of:maxBytes:) -> Data?`, `.stamp(of:) -> FileStamp?` with `FileStamp { size: Int; modified: Date }` (`Equatable`, `Sendable`).
  - `ProcessScanner.snapshot() -> [ProcessSnapshot]`.
  - `ClaudeCodeProvider(home: URL)` — `home` is `~/.claude`.
  - `AgentProviders.all() -> [any AgentSessionProvider]`.
  - `AgentSessionCoordinator(providers:isWatching:onUpdate:)`, `.start()`, `.stop()`.

- [ ] **Step 1: Bounded file reads**

`Symbiodock/Agents/FileReading.swift`:

```swift
import Darwin
import Foundation

/// A file's size and modification time: enough to tell whether it has to be read again.
struct FileStamp: Equatable, Sendable {
    let size: Int
    let modified: Date
}

/// Reads of other tools' files. Every read is bounded and read-only; a failure is nil.
enum FileReading {
    /// A plain `stat`: `FileManager.attributesOfItem` also reads extended attributes,
    /// which made it the most expensive part of a scan.
    static func stamp(of url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        let fraction = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileStamp(size: Int(info.st_size), modified: Date(timeIntervalSince1970: seconds + fraction))
    }

    /// The whole file, or nil if it is larger than `maxBytes`.
    static func whole(_ url: URL, maxBytes: Int) -> Data? {
        guard let stamp = stamp(of: url), stamp.size <= maxBytes else { return nil }
        return head(of: url, maxBytes: maxBytes)
    }

    /// At most the first `maxBytes` bytes.
    static func head(of url: URL, maxBytes: Int) -> Data? {
        guard maxBytes > 0, let handle = openRegularFile(url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }

    /// At most the last `maxBytes` bytes.
    static func tail(of url: URL, maxBytes: Int) -> Data? {
        guard maxBytes > 0, let handle = openRegularFile(url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        return try? handle.read(upToCount: maxBytes)
    }

    /// Opens a file for reading only if it is a regular file. The check is made on the
    /// open descriptor, so what was checked is what is read. A pipe or a device at the
    /// path would block the scan; it is opened without waiting (`O_NONBLOCK` lets the
    /// open of a pipe return at once) and then turned away.
    private static func openRegularFile(_ url: URL) -> FileHandle? {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            return nil
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
```

- [ ] **Step 2: The process scanner**

`Symbiodock/Agents/ProcessScanner.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore

/// Lists the running processes. Read-only, and nothing here asks for a permission.
/// Every process is listed with its parent, because the way from a tool up to its terminal
/// app passes through `login`, which belongs to root; the details (path, arguments,
/// folder) are read only for the current user's own processes.
///
/// An actor, because the path of a process is asked for only once and remembered: the
/// scan runs off the main actor, one scan at a time, and the memory belongs to it.
actor ProcessScanner {
    private static let pathBufferSize = 4096
    /// No command line of an agent tool needs more than its first arguments.
    private static let maximumArguments = 16

    /// A process is told apart from a later one that got its pid by the pair of both.
    private struct Identity: Hashable {
        let pid: pid_t
        let seconds: Int
        let microseconds: Int
    }

    /// Executable paths already read, for the processes still running.
    private var paths: [Identity: String] = [:]

    func snapshot() -> [ProcessSnapshot] {
        let uid = getuid()
        var processes: [ProcessSnapshot] = []
        var seen: Set<Identity> = []
        for entry in Self.processTable() {
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { continue }
            let isOwn = entry.kp_eproc.e_ucred.cr_uid == uid
            let device = entry.kp_eproc.e_tdev
            let started = entry.kp_proc.p_un.__p_starttime
            let identity = Identity(
                pid: pid, seconds: Int(started.tv_sec), microseconds: Int(started.tv_usec))
            var path = ""
            if isOwn {
                seen.insert(identity)
                if let known = paths[identity] {
                    path = known
                } else if let read = Self.executablePath(of: pid) {
                    paths[identity] = read
                    path = read
                }
            }
            processes.append(
                ProcessSnapshot(
                    pid: pid,
                    parentPID: entry.kp_eproc.e_ppid,
                    executablePath: path,
                    startTime: Date(
                        timeIntervalSince1970: TimeInterval(started.tv_sec)
                            + TimeInterval(started.tv_usec) / 1_000_000),
                    // -1 is NODEV: no controlling terminal.
                    terminal: isOwn && device != -1 && device != 0 ? device : nil))
        }
        // Forget the processes that are gone.
        if paths.count > seen.count {
            paths = paths.filter { seen.contains($0.key) }
        }

        // The expensive parts only where they can matter.
        for index in processes.indices where !processes[index].executablePath.isEmpty {
            if processes[index].terminal != nil,
               AgentProcessMatcher.isInterpreter(processes[index].executablePath) {
                processes[index].arguments = Self.arguments(of: processes[index].pid)
            }
            if AgentProcessMatcher.tool(for: processes[index]) != nil {
                processes[index].workingDirectory = Self.workingDirectory(of: processes[index].pid)
            }
        }
        return processes
    }

    /// The kernel's process table, as `ps` reads it.
    private static func processTable() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        // If many processes start between asking for the size and asking for the table,
        // the second call fails with ENOMEM. Ask again once, with more room, rather than
        // report an empty list, which would make every session vanish for a scan.
        for attempt in 0..<2 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
            // Room for processes that start between the two calls.
            var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32 + attempt * 256)
            var used = table.count * stride
            if sysctl(&mib, UInt32(mib.count), &table, &used, nil, 0) == 0 {
                return Array(table.prefix(used / stride))
            }
        }
        return []
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: pathBufferSize)
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length), as: UTF8.self)
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// `argv` of a process, from `KERN_PROCARGS2`: argc, the executable path, padding,
    /// then the arguments, each ending in a zero byte.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else { return [] }

        let count = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while index < size, arguments.count < min(count, maximumArguments) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
```

- [ ] **Step 3: The Claude Code provider**

`Symbiodock/Agents/ClaudeCodeProvider.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore

/// Claude Code keeps one small JSON file per running session in `~/.claude/sessions`,
/// with its name, folder and whether it is busy, idle or waiting for the user.
actor ClaudeCodeProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.claudeCode
    /// `~/.claude`
    private let home: URL

    /// What was read from a waiting session's transcript, until the file changes.
    private struct Asked {
        let stamp: FileStamp
        let question: String?
    }

    private var asked: [String: Asked] = [:]

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else {
            asked.removeAll()
            return []
        }

        var stillAsking: [String: Asked] = [:]
        defer { asked = stillAsking }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let stamp = FileReading.stamp(of: url),
                  let data = FileReading.whole(url, maxBytes: ClaudeSessionParser.maximumFileSize),
                  let record = ClaudeSessionParser.record(from: data),
                  Self.isLive(record.pid, modified: stamp.modified, among: context.processes)
            else { return nil }
            return ClaudeSessionParser.session(
                from: record,
                prompt: record.status == "waiting" ? question(of: record, remembering: &stillAsking) : nil,
                fallbackSince: stamp.modified)
        }
    }

    /// The question the session is waiting on, if its transcript shows one. The transcript
    /// is read again only when its size or modification time changed; `remembering`
    /// collects what is still in use, so that the questions of sessions that are gone are
    /// forgotten.
    private func question(
        of record: ClaudeSessionRecord, remembering kept: inout [String: Asked]
    ) -> String? {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let path = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return nil }
        let url = home.appendingPathComponent(path)
        guard let stamp = FileReading.stamp(of: url) else { return nil }
        if let known = asked[path], known.stamp == stamp {
            kept[path] = known
            return known.question
        }
        let question = FileReading.tail(of: url, maxBytes: ClaudeTranscriptPromptReader.tailSize)
            .flatMap(ClaudeTranscriptPromptReader.pendingQuestion(inTail:))
        kept[path] = Asked(stamp: stamp, question: question)
        return question
    }

    /// A session file can outlive its process, and its pid can then belong to anything.
    /// The process list the scan already has decides (see `ClaudeSessionParser.isLive`).
    /// Only when that list is empty, because the scan failed, is the pid probed, so that
    /// a failed scan does not make every session vanish. `EPERM` does not count: that pid
    /// belongs to another user.
    private nonisolated static func isLive(
        _ pid: Int32, modified: Date, among processes: [ProcessSnapshot]
    ) -> Bool {
        if processes.isEmpty { return kill(pid, 0) == 0 }
        return ClaudeSessionParser.isLive(pid: pid, fileModified: modified, among: processes)
    }
}
```

- [ ] **Step 4: The provider list**

`Symbiodock/Agents/AgentProviders.swift`:

```swift
import Foundation
import SymbiodockCore

/// Every tool whose sessions the island shows.
enum AgentProviders {
    static func all() -> [any AgentSessionProvider] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ClaudeCodeProvider(home: home.appendingPathComponent(".claude", isDirectory: true)),
        ]
    }
}
```

- [ ] **Step 5: The coordinator**

`Symbiodock/Agents/AgentSessionCoordinator.swift`:

```swift
import Foundation
import SymbiodockCore
import os

/// Asks the providers for their sessions again and again, off the main thread, and hands
/// the merged list to the app.
@MainActor
final class AgentSessionCoordinator {
    /// Counts and tool names only; never a title, a path or a question.
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "agents")
    /// Seconds between scans while nobody looks at the Agents tab.
    private static let restingInterval = 3

    private let providers: [any AgentSessionProvider]
    private let isWatching: @MainActor () -> Bool
    private let onUpdate: @MainActor ([AgentSession]) -> Void
    private var task: Task<Void, Never>?

    /// - Parameter isWatching: whether the Agents tab is on screen; then the scan runs every second.
    init(
        providers: [any AgentSessionProvider],
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor ([AgentSession]) -> Void
    ) {
        self.providers = providers
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard task == nil else { return }
        let providers = providers
        let scanner = ProcessScanner()
        task = Task { [weak self] in
            var lastCount = -1
            while !Task.isCancelled {
                // One scan at a time: the next starts only after this one has ended.
                let sessions = await Self.scan(providers, with: scanner)
                guard !Task.isCancelled, let self else { return }
                self.onUpdate(sessions)
                if sessions.count != lastCount {
                    lastCount = sessions.count
                    let tools = Set(sessions.map(\.tool.rawValue)).sorted().joined(separator: ",")
                    Self.log.notice("sessions: \(sessions.count, privacy: .public) [\(tools, privacy: .public)]")
                }
                // Wake early as soon as the Agents tab is being looked at.
                for _ in 0..<Self.restingInterval {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled || self.isWatching() { break }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Runs off the main actor: it reads files and the process list.
    nonisolated private static func scan(
        _ providers: [any AgentSessionProvider], with scanner: ProcessScanner
    ) async -> [AgentSession] {
        let processes = await scanner.snapshot()
        let context = AgentScanContext(now: Date(), processes: processes)
        var sessions: [AgentSession] = []
        for provider in providers {
            sessions += await provider.sessions(in: context)
        }
        return sessions.map { HostApp.resolving($0, in: processes) }
    }
}
```

- [ ] **Step 6: Start it from `AppDelegate`**

In `Symbiodock/App/AppDelegate.swift`:

1. Add the property `private var agents: AgentSessionCoordinator?`.

2. Replace the `#if DEBUG … DemoAgents … #endif` block from Task 2 with:

```swift
        #if DEBUG
        if let demo = DemoAgents.requested {
            DemoAgents.apply(demo, to: state)
            overlayController.refreshPointer()
        } else {
            startAgents()
        }
        #else
        startAgents()
        #endif
```

and add the method:

```swift
    /// Starts looking for agent sessions.
    private func startAgents() {
        let agents = AgentSessionCoordinator(
            providers: AgentProviders.all(),
            isWatching: { [weak self] in
                self.map { $0.state.phase == .expanded && $0.state.selectedTab == .agents } ?? false
            },
            onUpdate: { [weak self] sessions in
                guard let self else { return }
                let hadWings = self.state.showsWings
                self.state.setAgentSessions(sessions)
                // The collapsed hit rect depends on whether the wings are shown.
                if self.state.showsWings != hadWings { self.overlayController?.refreshPointer() }
            })
        agents.start()
        self.agents = agents
    }
```

3. In `applicationWillTerminate`, add `agents?.stop()`.

- [ ] **Step 7: Build and check against the live session**

This task is being carried out by a Claude Code session, so at least one real session exists while you test.

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
pkill -x Symbiodock; while pgrep -x Symbiodock >/dev/null; do sleep 0.1; done
(/usr/bin/log stream --style compact --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "agents"' > build/agents.log 2>&1 &) ; sleep 1
open build/Build/Products/Debug/Symbiodock.app; sleep 8
pkill -f 'log stream --style compact --predicate .subsystem == "com.yigtwxx.Symbiodock"'
cat build/agents.log; ls ~/.claude/sessions/*.json | wc -l
ps -o %cpu= -p "$(pgrep -x Symbiodock)"; sleep 20; ps -o %cpu= -p "$(pgrep -x Symbiodock)"
pkill -x Symbiodock
```

Expected: a line `sessions: N [claudeCode]` where N is the number of `.json` files whose process is alive (at least 1). The CPU figures are small; the second one, taken at rest, is under about 2 %. If N is 0 although a session file exists, find out why with evidence (is the pid alive, does the file parse) before changing code; do not print the file's contents into your report.

The app must not have shown any permission dialog. If one appeared, stop and report it.

- [ ] **Step 8: Commit**

```bash
git add Symbiodock docs/superpowers/plans
git commit -m "feat: list Claude Code sessions in the Agents tab"
git push origin main
```

---

### Task 5: Codex

**Files:**
- Create: `Symbiodock/Agents/CodexProvider.swift`
- Modify: `Symbiodock/Agents/AgentProviders.swift`

**Interfaces:**
- Consumes: core `CodexRolloutParser`, `CodexSessionIndex`, `CodexThreadMeta`, `CodexTurnState`, `AgentProcessMatcher`; `FileReading`, `FileStamp` (Task 4).
- Produces: `CodexProvider(home: URL)` — `home` is `~/.codex`.

- [ ] **Step 1: Write the provider**

`Symbiodock/Agents/CodexProvider.swift`:

```swift
import Foundation
import SymbiodockCore

/// Codex writes every thread to a rollout file. The file's first line says which thread
/// it is and its last turn event says whether a turn is running. Only these files and the
/// index of thread names are read; Codex's databases are left alone.
actor CodexProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.codex
    /// `~/.codex`
    private let home: URL
    /// How many day folders back a thread can still be alive in.
    private static let dayFolders = 3

    private struct Entry {
        let stamp: FileStamp
        let meta: CodexThreadMeta?
        let state: CodexTurnState?
    }

    /// What was read from each rollout, until the file changes.
    private var cache: [String: Entry] = [:]
    private var titles: [String: String] = [:]
    private var titlesStamp: FileStamp?

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let codex = context.processes.filter { AgentProcessMatcher.tool(for: $0) == .codex }
        // A thread is live only while Codex itself runs.
        guard !codex.isEmpty else {
            cache.removeAll()
            return []
        }

        var sessions: [AgentSession] = []
        var live: [String: Entry] = [:]
        for url in recentRollouts() {
            guard let stamp = FileReading.stamp(of: url),
                  context.now.timeIntervalSince(stamp.modified) <= CodexRolloutParser.workingListing
            else { continue }
            let entry = entry(for: url, stamp: stamp)
            live[url.path] = entry
            guard let meta = entry.meta, !meta.isSubagent, let state = entry.state,
                  CodexRolloutParser.isListed(state, modified: stamp.modified, now: context.now)
            else { continue }
            sessions.append(
                CodexRolloutParser.session(
                    meta: meta, state: state, title: title(of: meta.id),
                    pid: Self.process(for: meta, among: codex)))
        }
        cache = live
        return sessions
    }

    /// Parses a rollout again only if it changed; the first line never changes.
    private func entry(for url: URL, stamp: FileStamp) -> Entry {
        let known = cache[url.path]
        if let known, known.stamp == stamp { return known }
        let meta = known?.meta
            ?? FileReading.head(of: url, maxBytes: CodexRolloutParser.headSize)
                .flatMap(CodexRolloutParser.meta(fromHead:))
        let state = FileReading.tail(of: url, maxBytes: CodexRolloutParser.tailSize)
            .flatMap(CodexRolloutParser.turnState(inTail:))
        return Entry(stamp: stamp, meta: meta, state: state)
    }

    /// The rollout files in the newest day folders, `sessions/YYYY/MM/DD/`.
    private func recentRollouts() -> [URL] {
        let root = home.appendingPathComponent("sessions", isDirectory: true)
        var days: [URL] = []
        for year in Self.folders(in: root) {
            for month in Self.folders(in: year) {
                for day in Self.folders(in: month) {
                    days.append(day)
                    if days.count == Self.dayFolders { break }
                }
                if days.count == Self.dayFolders { break }
            }
            if days.count == Self.dayFolders { break }
        }
        return days.flatMap { day in
            ((try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        }
    }

    /// Sub-folders, newest name first. The names are zero-padded numbers.
    private static func folders(in url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func title(of id: String) -> String? {
        let url = home.appendingPathComponent("session_index.jsonl")
        if let stamp = FileReading.stamp(of: url), stamp != titlesStamp {
            titlesStamp = stamp
            titles = FileReading.tail(of: url, maxBytes: CodexRolloutParser.tailSize)
                .map(CodexSessionIndex.titles(from:)) ?? [:]
        }
        return titles[id]
    }

    /// The Codex process a thread belongs to: the only one running in the thread's folder,
    /// or, for a desktop thread, the desktop app's own Codex process.
    private static func process(
        for meta: CodexThreadMeta, among codex: [ProcessSnapshot]
    ) -> Int32? {
        let inFolder = codex.filter { $0.workingDirectory != nil && $0.workingDirectory == meta.cwd }
        if inFolder.count == 1 { return inFolder[0].pid }
        if meta.originator == "Codex Desktop" {
            return codex.first { $0.terminal == nil }?.pid
        }
        return nil
    }
}
```

- [ ] **Step 2: Add it to the list**

In `Symbiodock/Agents/AgentProviders.swift`, the returned array becomes:

```swift
        return [
            ClaudeCodeProvider(home: home.appendingPathComponent(".claude", isDirectory: true)),
            CodexProvider(home: home.appendingPathComponent(".codex", isDirectory: true)),
        ]
```

- [ ] **Step 3: Build and check against real Codex data**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
pgrep -fl 'MacOS/codex$' | wc -l
find ~/.codex/sessions -name 'rollout-*.jsonl' -mmin -30 | wc -l
pkill -x Symbiodock; while pgrep -x Symbiodock >/dev/null; do sleep 0.1; done
(/usr/bin/log stream --style compact --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "agents"' > build/agents.log 2>&1 &) ; sleep 1
open build/Build/Products/Debug/Symbiodock.app; sleep 8
pkill -f 'log stream --style compact --predicate .subsystem == "com.yigtwxx.Symbiodock"'
cat build/agents.log
ps -o %cpu= -p "$(pgrep -x Symbiodock)"; pkill -x Symbiodock
```

Expected: if a Codex process runs and a root thread's rollout changed in the last 30 minutes, the log line names `codex` beside `claudeCode`. If Codex is not running or no rollout is recent, the line has `claudeCode` only, which is correct: say in the report which case you saw and the two counts printed above. Do not start Codex or write into `~/.codex` to force a result.

- [ ] **Step 4: Commit**

```bash
git add Symbiodock docs/superpowers/plans
git commit -m "feat: list Codex threads in the Agents tab"
git push origin main
```

---

### Task 6: Process-level tools and jumping to a session

**Files:**
- Create: `Symbiodock/Agents/HostApp.swift`
- Modify: `Symbiodock/Agents/AgentProviders.swift`
- Modify: `Symbiodock/Agents/AgentSessionCoordinator.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: core `ProcessLevelProvider`, `ProcessTree`, `AgentSession.hostAppPID`.
- Produces: `HostApp.resolving(_ session: AgentSession, in: [ProcessSnapshot]) -> AgentSession` (nonisolated), `HostApp.bringForward(pid: Int32)` (main actor).

- [ ] **Step 1: Find and activate the hosting app**

`Symbiodock/Agents/HostApp.swift`:

```swift
import AppKit
import SymbiodockCore

/// The app a session runs in: the terminal or editor above the tool's process.
enum HostApp {
    /// Fills in `hostAppPID`: the nearest process, from the tool's own upward, that is a
    /// regular app. A chain that ends in `tmux` or `launchd` has none, and stays nil.
    static func resolving(_ session: AgentSession, in processes: [ProcessSnapshot]) -> AgentSession {
        guard let pid = session.pid else { return session }
        var session = session
        session.hostAppPID = ([pid] + ProcessTree.ancestors(of: pid, in: processes)).first {
            NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular
        }
        return session
    }

    /// Brings the app forward. Opening it again is what reliably activates an app from an
    /// agent app like this one; plain activation is the fallback.
    @MainActor
    static func bringForward(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }
}
```

- [ ] **Step 2: Resolve the host in the scan**

In `AgentSessionCoordinator.scan`, replace the body with:

```swift
        let processes = ProcessScanner.snapshot()
        let context = AgentScanContext(now: Date(), processes: processes)
        var sessions: [AgentSession] = []
        for provider in providers {
            sessions += await provider.sessions(in: context)
        }
        return sessions.map { HostApp.resolving($0, in: processes) }
```

- [ ] **Step 3: Add the five process-level tools**

In `AgentProviders.all()`, the returned array becomes:

```swift
        let processLevel: [AgentTool] = [.geminiCLI, .cursorAgent, .openCode, .aider, .copilotCLI]
        return [
            ClaudeCodeProvider(home: home.appendingPathComponent(".claude", isDirectory: true)),
            CodexProvider(home: home.appendingPathComponent(".codex", isDirectory: true)),
        ] + processLevel.map { ProcessLevelProvider(tool: $0) }
```

- [ ] **Step 4: Make a click open the session**

In `AppDelegate`, replace `onOpenSession: { _ in })` with:

```swift
            onOpenSession: { session in
                if let pid = session.hostAppPID { HostApp.bringForward(pid: pid) }
            })
```

- [ ] **Step 5: Build and check with a stand-in process**

None of the five tools is installed here, so a stand-in named like one is run under a terminal:

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
mkdir -p build/fake && printf 'import Foundation\nsleep(45)\n' > build/fake/main.swift && swiftc -o build/fake/opencode build/fake/main.swift
(cd build && script -q /dev/null fake/opencode >/dev/null 2>&1 &)
sleep 1; ps -o pid,tty,comm -p "$(pgrep -f 'fake/opencode$' | head -1)"
pkill -x Symbiodock; while pgrep -x Symbiodock >/dev/null; do sleep 0.1; done
(/usr/bin/log stream --style compact --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "agents"' > build/agents.log 2>&1 &) ; sleep 1
open build/Build/Products/Debug/Symbiodock.app; sleep 8
pkill -f 'log stream --style compact --predicate .subsystem == "com.yigtwxx.Symbiodock"'
cat build/agents.log; pkill -x Symbiodock; pkill -f 'fake/opencode$'
```

Expected: `ps` shows the stand-in with a terminal (not `??`), and the log line names `openCode` beside the others. If `ps` shows `??`, the stand-in got no terminal: say so and try `script -q /dev/null build/fake/opencode` from the project root; the detection code is not at fault in that case.

Bringing an app forward cannot be checked without a click on the island; it is on the owner's checklist.

- [ ] **Step 6: Commit**

```bash
git add Symbiodock docs/superpowers/plans
git commit -m "feat: detect five more agent tools and open a session's app"
git push origin main
```

---

## After the tasks

Changes made after the tasks above, on the owner's word and from the reviews; the code in
the repository is the reference where it differs from a block quoted in a task.

- **Cost of animation.** While any view redraws more often than about every 0.35 s, SwiftUI keeps the full-screen panel's update cycle running, which alone costs about 5 % of a core. So the pets stir a few times a second, the turning arc and the rim's breath run in Core Animation (`LayerAnimation.swift`), and hops, knocks and the passing highlight redraw only while they last (`FrameSchedule.swift`). When a frame is due is decided by `FramePacer` in the core package, which is tested never to repeat a moment: a schedule that did repeat one hung the app on the main thread once.
- **Colour runs.** Each pet's colour runs from its upper left to its lower right (`AgentPalette.run(for:)`), instead of being one colour.
- **The lip.** The island with its wings is `IslandLayout.notchLip` (2 pt) taller than the notch, so the rim light passes under the camera housing unbroken. Setting it to 0 gives the old look, where the light is cut in the middle.
- **Reading cost.** `ProcessScanner` keeps each process's path by pid and start time; `ClaudeCodeProvider` reads a transcript again only when it changed.

## Hand checklist for the owner

Build and start:

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
pkill -x Symbiodock; open build/Build/Products/Debug/Symbiodock.app
```

Tabs:

0. In every row and on the collapsed island each tool is shown by its pet, a small figure made of vertical bars in the tool's colour: an orange blocky creature for Claude Code, a blue cloud for Codex. They look clean at both sizes. While a session works its pet's bars move like a wave; while it needs input the pet hops.
1. Hover the island. Two glyphs are at its top left (sparkles, music note); the selected one is bright with a dot under it. Click each: the content changes, the music controls still work.
2. Right-click → `First tab` → `Media`. Play music and keep a Claude Code session working: the collapsed island shows the artwork and level bars. Choose `Agents`: it shows the pet and the turning mark instead. Quit and relaunch: the choice is kept.
3. With music paused for more than 10 seconds and no agent working, the island at the notch is the bare notch again.

Claude Code:

4. Start a Claude Code session in a terminal and give it a task. Within three seconds the collapsed island widens: its pet left, a turning arc right. Hover: the row shows the session's name, its folder, `Working …`.
5. Let Claude Code ask a question (or a permission). The island does **not** open. The red light runs around the island and passes **under the camera housing** without a break; the island is only a hair taller than the notch and does not look clumsy (if it does: `IslandLayout.notchLip` back to 0).
   Also: the island does **not** open. The mark turns into a red ring whose dot knocks twice, and a red light breathes along the island's lower rim with a highlight passing every few seconds.
6. Hover: the Agents tab opens whichever tab is first. The row is tinted, says `Needs input`, and shows the question on a second line. Answer in the terminal: the row goes back to `Working`.
7. Let the task finish. The mark becomes a mint ring with a check mark that draws itself, and a mint light passes once and stays as a thin line. Hover: the row says `Done …`. Move away: the light and the check mark are gone; the row is `Idle …` the next time.
8. Click a row. Its terminal (or editor) comes to the front.
9. Close the session. Its row disappears within three seconds.

Codex:

10. Start a turn in Codex (desktop or CLI). A `Codex` row with the thread's name says `Working …`, then `Done …` when the turn ends. Clicking it brings Codex forward.

Other tools (if you have one of Gemini CLI, Cursor Agent, OpenCode, Aider, Copilot CLI):

11. Start it in a terminal. A row with its name and folder says `Running`. It never says working or done. Clicking it brings the terminal forward.

Everywhere:

12. Dock the island on the bottom edge and on the right edge and repeat 4–7: the capsule shows pet, name and mark; the strip shows them top to bottom; the light runs along the free edges only.
13. With three or more sessions, two are visible, one under the other; the list scrolls with two fingers and comes to rest on a row.
14. System Settings → Accessibility → Display → Reduce motion on: marks and light are still, in their colour.
15. At rest (no hover), Activity Monitor shows Symbiodock near 0 % CPU; with one agent working it stays low.
16. No macOS permission dialog appeared at any point.

To see what the scan finds without any content: `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "agents"'` prints a count and the tool names whenever the count changes.

To look at every state without running an agent: `pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=1 build/Build/Products/Debug/Symbiodock.app` (also `working`, `finished`, `quiet`).

## Spec coverage

| Spec section | Task |
|---|---|
| 5 Tab strip, summary, `First tab` menu, stored order | 2 |
| 6.1 Claude Code provider | 4 |
| 6.2 Codex provider | 5 |
| 6.3 Process-level tools | 6 |
| 6.4 Coordinator: intervals, one scan at a time | 4 |
| 7.1 Status mark | 1 |
| 7.2 Rim light, Reduce Motion | 3 |
| 7.3 Collapsed faces in three forms | 3 |
| 7.4 Agents tab rows, labels, empty state | 2 |
| 7.5 Pets | 1 (figures: core plan Task 6) |
| 8 Jumping to a session | 6 |
| 9 Error handling at the file and process boundary | 4, 5 |
| 10 Off-screen renders, hand checklist | 1, 2, 3, this file |

Spec section 6.3's research task per process-level tool is not a code task: it is done alongside, and its outcome is recorded in `CLAUDE.md`.

## Animation cost (added after review)

The island is always on screen, so animation must cost almost nothing. Measured: while a view redraws more often than about every 0.35 s, SwiftUI keeps the full-screen panel's update cycle running at the screen's rate, which costs about 5 % of a core whatever the view draws. Redrawing every 0.4 s or less often costs nothing measurable. So the pets stir at 2.5 frames a second (24 pt; the stir moves under a point), bursts such as hops, knocks and the rim's passing highlight redraw only while they last (`FrameSchedule` with a `Pulse`), and motion that must be smooth and never rests (the working spinner, the rim's breath) is played by Core Animation. Never replace these with `TimelineView(.animation)` without measuring again.

`Symbiodock/Island/FrameSchedule.swift`:

```swift
import SwiftUI
import SymbiodockCore

// How the island's animations are paced.
//
// Measured on the always-on island: while a view redraws more often than about every
// 0.35 s, SwiftUI keeps the full-screen panel's update cycle running at the screen's rate,
// and that alone costs about 5 % of a core, whatever the view draws (an empty `Canvas`
// costs the same). Redrawing every 0.4 s or less often costs nothing measurable. So:
// motion that is slow enough for a few frames a second uses `FrameSchedule`; short
// motions that repeat with rests between use `FrameSchedule` with a `Pulse`, which draws
// only while the motion lasts; and motion that has to be smooth and never rests is handed to Core
// Animation (see `SpinningArc`, `Breathing`), which runs in the render server and costs
// the app nothing.

/// Draws a `TimelineView` from a timer, `interval` seconds apart. With a `pulse` it draws
/// only while the motion lasts and once more at its end, so that the view comes to rest.
/// The stepping is `FramePacer`'s, in the core package, where it is tested never to stand
/// still: a schedule that repeats a date makes SwiftUI spin on the main thread. It also
/// starts again from the present after sleep or a clock change.
struct FrameSchedule: TimelineSchedule {
    typealias Pulse = FramePacer.Pulse

    let interval: TimeInterval
    var pulse: Pulse?
    /// A paused schedule gives one date and stops: the view is drawn once.
    var paused = false

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(pacer: FramePacer(interval: interval, pulse: pulse, paused: paused, from: startDate))
    }

    struct Entries: Sequence, IteratorProtocol {
        var pacer: FramePacer

        mutating func next() -> Date? {
            pacer.next(now: Date())
        }
    }
}
```

`Symbiodock/Island/LayerAnimation.swift`:

```swift
import AppKit
import SwiftUI

// Motion that must be smooth and never rests, run by Core Animation. The render server
// plays these; the app does no work per frame (see `FrameSchedule` for why that matters).

/// An arc that turns about its centre: the status mark's working spinner. It fills its
/// frame the way a SwiftUI `Circle` does and starts at 12 o'clock, going clockwise.
struct SpinningArc: NSViewRepresentable {
    let color: Color
    let lineWidth: CGFloat
    /// Seconds for one turn.
    let period: TimeInterval
    /// The share of the circle that is drawn.
    var sweep: Double = 0.75

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.configure(color: NSColor(color), lineWidth: lineWidth, period: period, sweep: sweep)
    }

    final class ArcView: NSView {
        private let arc = CAShapeLayer()
        private var period: TimeInterval = 1
        private var sweep = 0.75

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineCap = .round
            layer?.addSublayer(arc)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(color: NSColor, lineWidth: CGFloat, period: TimeInterval, sweep: Double) {
            arc.strokeColor = color.cgColor
            arc.lineWidth = lineWidth
            if self.period != period || self.sweep != sweep {
                self.period = period
                self.sweep = sweep
                needsLayout = true
            }
            startSpinning()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            let radius = min(bounds.width, bounds.height) / 2
            let path = CGMutablePath()
            // In the layer's own coordinates y points up, so clockwise runs to smaller angles.
            path.addArc(
                center: CGPoint(x: bounds.width / 2, y: bounds.height / 2), radius: radius,
                startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * sweep, clockwise: true)
            arc.path = path
            CATransaction.commit()
            startSpinning()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startSpinning()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            arc.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func startSpinning() {
            guard window != nil else { return }
            if let known = arc.animation(forKey: "spin") as? CABasicAnimation, known.duration == period {
                return
            }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = period
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.isRemovedOnCompletion = false
            arc.add(spin, forKey: "spin")
        }
    }
}

/// SwiftUI content whose opacity rises and falls by itself, run by Core Animation:
/// the rim light's breath. The content is drawn once, at its brightest.
struct Breathing<Content: View>: NSViewRepresentable {
    /// The opacity at the dimmest point, 0...1 of the content's own.
    let dimmest: Float
    /// Seconds for a whole breath, in and out.
    let period: TimeInterval
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> Host {
        let host = Host(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []
        return host
    }

    func updateNSView(_ host: Host, context: Context) {
        host.rootView = content
        host.configure(dimmest: dimmest, period: period)
    }

    final class Host: NSHostingView<Content> {
        private var dimmest: Float = 1
        private var period: TimeInterval = 1

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(dimmest: Float, period: TimeInterval) {
            let changed = self.dimmest != dimmest || self.period != period
            self.dimmest = dimmest
            self.period = period
            startBreathing(replacing: changed)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startBreathing(replacing: false)
        }

        private func startBreathing(replacing: Bool) {
            guard window != nil, let layer else { return }
            if replacing { layer.removeAnimation(forKey: "breath") }
            if layer.animation(forKey: "breath") != nil { return }
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 1.0
            breath.toValue = dimmest
            breath.duration = period / 2
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath.isRemovedOnCompletion = false
            layer.add(breath, forKey: "breath")
        }
    }
}
```
