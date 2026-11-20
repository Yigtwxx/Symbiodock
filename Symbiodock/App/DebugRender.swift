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
        write(TabGlyphGallery(), size: CGSize(width: 880, height: 290), named: "tab-glyphs", to: directory)
        write(StatusMarkGallery(), size: CGSize(width: 900, height: 150), named: "status-marks", to: directory)
        write(PetGallery(), size: CGSize(width: 800, height: 460), named: "pets", to: directory)
        write(SealGallery(), size: CGSize(width: 640, height: 150), named: "finish-seal", to: directory)
        for (name, tab) in [("expanded-agents", IslandTab.agents), ("expanded-media", .media)] {
            let state = IslandState()
            DemoAgents.apply("1", to: state)
            state.setHovering(true)
            state.selectTab(tab)
            write(
                ExpandedPreview(state: state), size: CGSize(width: 640, height: 210),
                named: name, to: directory)
        }
        let files = IslandState()
        files.setHovering(true)
        files.selectTab(.files)
        write(
            ExpandedPreview(state: files), size: CGSize(width: 640, height: 210),
            named: "expanded-files-empty", to: directory)
        let previews = FilePreviews()
        let shelf = IslandState()
        DemoFiles.apply("1", to: shelf, previews: previews)
        shelf.setHovering(true)
        shelf.selectTab(.files)
        write(
            ExpandedPreview(state: shelf, previews: previews), size: CGSize(width: 640, height: 210),
            named: "expanded-files", to: directory)
        // The pointer on the drawer's back tab: the tab rises, clear of the tab strip above.
        if let drawer = shelf.shelf.stacks.first {
            shelf.setHoveredFile(ShelfHover(stack: drawer.id, hit: .file(drawer.items.count - 1)))
            write(
                ExpandedPreview(state: shelf, previews: previews), size: CGSize(width: 640, height: 210),
                named: "expanded-files-hover", to: directory)
            shelf.setHoveredFile(nil)
        }
        // The drawer and the photo beside it, picked together.
        let several = IslandState()
        DemoFiles.apply("1", to: several, previews: previews)
        several.toggleShelfItems(several.shelf.items.filter { $0.name == "Holiday.heic" }.map(\.id))
        several.setHovering(true)
        several.selectTab(.files)
        write(
            ExpandedPreview(state: several, previews: previews), size: CGSize(width: 640, height: 210),
            named: "expanded-files-multi", to: directory)
        write(
            FileStacksGallery(previews: previews), size: CGSize(width: 760, height: 200),
            named: "file-stacks", to: directory)
        shelf.setFileDragHovering(true)
        write(
            ExpandedPreview(state: shelf, previews: previews), size: CGSize(width: 640, height: 210),
            named: "expanded-files-drop", to: directory)
        files.setFileDragHovering(true)
        write(
            ExpandedPreview(state: files), size: CGSize(width: 640, height: 210),
            named: "expanded-files-empty-drop", to: directory)
        let twoSources = IslandState()
        DemoMedia.apply(to: twoSources, twoSources: true, otherApp: false)
        twoSources.setHovering(true)
        twoSources.selectTab(.media)
        write(
            ExpandedPreview(state: twoSources), size: CGSize(width: 640, height: 210),
            named: "expanded-media-two", to: directory)
        write(
            MediaStackGallery(slots: twoSources.mediaSlots), size: CGSize(width: 320, height: 150),
            named: "collapsed-media-two", to: directory)
        write(
            BubbleGallery(slots: twoSources.mediaSlots), size: CGSize(width: 380, height: 170),
            named: "collapsed-bubble", to: directory)
        let held = IslandState()
        DemoFiles.apply("1", to: held, previews: previews)
        write(
            FilesBubbleGallery(shelf: held.shelf, slots: twoSources.mediaSlots),
            size: CGSize(width: 420, height: 210), named: "collapsed-files-bubble", to: directory)
        let otherApp = IslandState()
        DemoMedia.apply(to: otherApp, twoSources: false, otherApp: true)
        otherApp.setHovering(true)
        otherApp.selectTab(.media)
        write(
            ExpandedPreview(state: otherApp), size: CGSize(width: 640, height: 210),
            named: "expanded-media-client", to: directory)
        write(
            MediaStackGallery(slots: otherApp.mediaSlots), size: CGSize(width: 320, height: 150),
            named: "collapsed-media-client", to: directory)
        let oneSource = IslandState()
        DemoMedia.apply(to: oneSource, twoSources: false, otherApp: false)
        oneSource.setHovering(true)
        oneSource.selectTab(.media)
        write(
            ExpandedPreview(state: oneSource), size: CGSize(width: 640, height: 210),
            named: "expanded-media-volume", to: directory)
        write(
            TrackGlowGallery(info: oneSource.mediaSlots[0].info), size: CGSize(width: 760, height: 500),
            named: "track-glow", to: directory)
        let empty = IslandState()
        empty.setHovering(true)
        empty.selectTab(.agents)
        write(
            ExpandedPreview(state: empty), size: CGSize(width: 640, height: 210),
            named: "expanded-agents-empty", to: directory)
        let branches = IslandState()
        DemoAgents.apply("branches", to: branches)
        branches.setHovering(true)
        branches.selectTab(.agents)
        write(
            ExpandedPreview(state: branches), size: CGSize(width: 640, height: 210),
            named: "expanded-agents-branches", to: directory)
        write(CollapsedGallery(), size: CGSize(width: 620, height: 540), named: "collapsed-faces", to: directory)
        write(WorkingAuroraGallery(), size: CGSize(width: 900, height: 640), named: "working-aurora", to: directory)
        // The goo that swallows a tile while its file changes format, over a photo becoming a
        // PNG and over a drawer whose documents become PDFs (the slides cannot, but they share
        // the drawer's cocoon).
        write(
            EngulfGallery(names: ["Holiday.heic"], chip: "PNG", previews: previews),
            size: CGSize(width: 760, height: 260), named: "engulf", to: directory)
        write(
            EngulfGallery(names: ["Report.docx", "Notes.docx", "Slides.pptx"], chip: "PDF", previews: previews),
            size: CGSize(width: 760, height: 260), named: "engulf-stack", to: directory)
        // The same drawer on its page, as its chip has just been pressed.
        let converting = IslandState()
        DemoFiles.apply("1", to: converting, previews: previews)
        for id in ConversionCatalog.plan(label: "PDF", items: converting.shelf.selectedItems).targets.keys {
            converting.beginConversion(id, label: "PDF", at: Date())
        }
        converting.setHovering(true)
        converting.selectTab(.files)
        write(
            ExpandedPreview(state: converting, previews: previews).environment(\.frozenEngulf, .engulf(0.6)),
            size: CGSize(width: 640, height: 210), named: "expanded-files-converting", to: directory)
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
    private static let states: [(String, AgentRowState, TimeInterval, AgentTool?)] = [
        ("working", .working, 0.2, nil),
        ("claude", .working, 0.2, .claudeCode),
        ("codex", .working, 0.5, .codex),
        ("compacting", .compacting, 0.3, nil),
        ("knock", .needsInput(prompt: nil), 0.15, nil),
        ("ripple", .needsInput(prompt: nil), 0.7, nil),
        ("finished", .finished, 0, nil),
        ("running", .running, 0, nil),
        ("idle", .idle, 0, nil),
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                ForEach(Self.states, id: \.0) { name, state, time, tool in
                    VStack(spacing: 8) {
                        AgentStatusMark(state: state, size: 42, tool: tool, frozenAt: time)
                            .frame(width: 60, height: 60)
                        AgentStatusMark(state: state, tool: tool, frozenAt: time)
                        Text(name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                // The live arc (Core Animation layers), at rest: the same mark as `claude`.
                VStack(spacing: 8) {
                    AgentStatusMark(state: .working, size: 42, tool: .claudeCode)
                        .frame(width: 60, height: 60)
                    AgentStatusMark(state: .working, tool: .claudeCode)
                    Text("claude live").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
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
                caption("compacting").frame(width: 44)
                ForEach([0.3, 0.65, 1.0], id: \.self) { time in
                    AgentPet(tool: .claudeCode, state: .compacting, size: 48, frozenAt: time)
                    AgentPet(tool: .codex, state: .compacting, size: 48, frozenAt: time)
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

/// The open island as it is at the notch: 600 × 150, with a 200 × 32 camera housing.
private struct ExpandedPreview: View {
    let state: IslandState
    var previews: FilePreviews?

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        ExpandedIsland(
            state: state,
            metrics: ExpandedHeaderMetrics(height: 32, leading: 200, gap: 200, trailing: 200),
            onCommand: { _, _ in }, onOpenSession: { _ in }, previews: previews)
            .frame(
                width: IslandLayout.expandedSize.width, height: IslandLayout.expandedSize.height
            )
            .background(.black, in: shape)
            .clipShape(shape)
    }
}

/// Drawers of every size, and a three-file drawer in each state the pointer and a drag give
/// it, frozen (there is no pointer in a render).
private struct FileStacksGallery: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let caption: String
        let stack: ShelfStack
        var hover: StackLayout.Hit?
        var isDropTarget = false
        var selection: Set<UUID> = []
    }

    let previews: FilePreviews
    /// Made once: staging the pictures while drawing would redraw the gallery for ever.
    private let samples: [Sample]

    init(previews: FilePreviews) {
        self.previews = previews
        func stack(_ names: [String]) -> ShelfStack {
            let id = UUID()
            let items = names.map { DemoFiles.item($0, stack: id) }
            DemoFiles.stage(items, in: previews)
            return FileShelf(items: items).stacks[0]
        }
        let drawer = ["Report.docx", "Invoice.pdf", "Archive.zip"]
        let middle = stack(drawer)
        samples = [
            Sample(caption: "1", stack: stack(["Holiday.heic"])),
            Sample(caption: "2", stack: stack(["Invoice.pdf", "Notes.docx"])),
            Sample(caption: "3", stack: stack(drawer)),
            Sample(caption: "5", stack: stack(["Holiday.heic", "Invoice.pdf", "Mix.wav", "Archive.zip", "Clip.mov"])),
            Sample(
                caption: "9",
                stack: stack([
                    "Photos/", "Report.docx", "Invoice.pdf", "Holiday.heic", "Mix.wav", "Clip.mov",
                    "Archive.zip", "Notes.docx", "Slides.pptx",
                ])),
            Sample(caption: "back tab", stack: stack(drawer), hover: .file(2)),
            Sample(caption: "grip", stack: stack(drawer), hover: .file(0)),
            Sample(caption: "body", stack: stack(drawer), hover: .body),
            Sample(caption: "drop target", stack: stack(drawer), isDropTarget: true),
            Sample(caption: "middle picked", stack: middle, selection: [middle.items[1].id]),
        ]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(samples) { sample in
                VStack(spacing: 8) {
                    StackTile(
                        stack: sample.stack, selection: sample.selection, hover: sample.hover,
                        isDropTarget: sample.isDropTarget, conversion: nil, previews: previews)
                    Text(sample.caption)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: StackLayout.tile.width)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A converting stack at moments of its goo's run, picked as it is when its chip is pressed.
/// Under the reveal lies what the files became: the same pictures, the new badge.
private struct EngulfGallery: View {
    private static let phases: [(String, EngulfPhase)] = [
        ("engulf .20", .engulf(0.2)), ("engulf .45", .engulf(0.45)), ("engulf .70", .engulf(0.7)),
        ("engulf .90", .engulf(0.9)), ("cocoon", .cocoon), ("reveal .25", .reveal(0.25)),
        ("reveal .55", .reveal(0.55)), ("reveal .85", .reveal(0.85)),
    ]

    let previews: FilePreviews
    /// Made once: staging the pictures while drawing would redraw the gallery for ever.
    private let before: ShelfStack
    private let after: ShelfStack

    /// The files `names` as pressing `chip` leaves them: those that offer it in its format.
    init(names: [String], chip: String, previews: FilePreviews) {
        self.previews = previews
        let drawer = names.count > 1 ? UUID() : nil
        let items = names.map { DemoFiles.item($0, stack: drawer) }
        DemoFiles.stage(items, in: previews)
        let plan = ConversionCatalog.plan(label: chip, items: items)
        let converted = items.map { item -> ShelfItem in
            guard let target = plan.targets[item.id] else { return item }
            let new = ShelfItem(
                url: item.url.deletingPathExtension().appendingPathExtension(target.pathExtension),
                isDirectory: false, stack: drawer)
            previews.stage(new, image: previews.image(for: item), bytes: nil)
            return new
        }
        before = FileShelf(items: items).stacks[0]
        after = FileShelf(items: converted).stacks[0]
    }

    var body: some View {
        let conversion = FileConversion(label: "", started: .distantPast)
        HStack(alignment: .bottom, spacing: 20) {
            ForEach(Self.phases, id: \.0) { caption, phase in
                let stack = if case .reveal = phase { after } else { before }
                VStack(spacing: 12) {
                    StackTile(
                        stack: stack, selection: Set(stack.items.map(\.id)), hover: nil,
                        isDropTarget: false, conversion: conversion, previews: previews)
                    .environment(\.frozenEngulf, phase)
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 30)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        case .compacting: board.update([session(.compacting)])
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

    private func compactingNotch(at time: TimeInterval) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: .notch, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: radii.bottomLeading, bottomTrailingRadius: radii.bottomTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentNotchFace(row: row(.compacting), notchWidth: 200) }
            .overlay { CompactingRim(radii: radii, dockedEdges: [.top], frozenAt: time) }
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

    /// The strip with no agent running, as an island docked on the right edge shows it.
    private var idleStrip: some View {
        let anchor = IslandAnchor.edge(.right, fraction: 0.5)
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentSideFace(row: nil) }
            .frame(width: 36, height: 170)
            .clipShape(shape)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                notch(.working, .none, at: 0)
                compactingNotch(at: 0.1)
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
            idleStrip
        }
        .padding(16)
    }
}

/// The collapsed media faces while two sources play: at the notch and as a capsule.
private struct MediaStackGallery: View {
    let slots: [NowPlayingSlot]

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
        VStack(spacing: 14) {
            CollapsedContent(info: slots[0].info, behind: slots[1].info, notchWidth: 200)
                .frame(width: 272, height: 32)
                .background(.black, in: shape)
            CollapsedContent(info: slots[0].info, notchWidth: 200)
                .frame(width: 272, height: 32)
                .background(.black, in: shape)
            FloatingCollapsedContent(info: slots[0].info, behind: slots[1].info)
                .frame(width: 200, height: 36)
                .background(.black, in: Capsule())
        }
        .padding(16)
    }
}

/// The light that greets a new track at four moments (spreading, arriving, whole, fading): at
/// the notch, round the bubble, on a capsule docked at the bottom and on a strip docked right.
private struct TrackGlowGallery: View {
    let info: NowPlayingInfo

    private static let times: [TimeInterval] = [0.08, 0.25, 0.75, 1.25]

    private var tint: ArtworkTint? { ArtworkCache.tint(for: info.artworkData) }

    private var lead: AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: .claudeCode, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func island(
        _ anchor: IslandAnchor, _ size: CGSize, at time: TimeInterval, @ViewBuilder face: () -> some View
    ) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { face() }
            .overlay {
                TrackGlowLine(
                    outline: .island(radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: anchor)),
                    tint: tint, isVertical: IslandLayout.isSideDocked(anchor), frozenAt: time)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
    }

    private func notch(at time: TimeInterval) -> some View {
        island(.notch, CGSize(width: 272, height: 32 + IslandLayout.notchLip), at: time) {
            CollapsedContent(info: info, notchWidth: 200)
                .padding(.bottom, IslandLayout.notchLip)
        }
    }

    private func bubble(at time: TimeInterval) -> some View {
        HStack(spacing: IslandLayout.bubbleGap) {
            SideBubble(content: .media(front: info, behind: nil), diameter: 28)
                .overlay {
                    TrackGlowLine(outline: .bubble, tint: tint, frozenAt: time)
                        .clipShape(Circle())
                }
            AgentNotchFace(row: lead, notchWidth: 200)
                .frame(width: 272, height: 32)
                .background(
                    .black,
                    in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.times, id: \.self) { notch(at: $0) }
                ForEach(Self.times, id: \.self) { bubble(at: $0) }
                ForEach([0.25, 0.75], id: \.self) { time in
                    island(.edge(.bottom, fraction: 0.5), IslandLayout.floatingCollapsedSize, at: time) {
                        FloatingCollapsedContent(info: info)
                    }
                }
            }
            ForEach([0.25, 0.75], id: \.self) { time in
                island(.edge(.right, fraction: 0.5), IslandLayout.sideCollapsedSize, at: time) {
                    SideCollapsedContent(info: info)
                }
            }
        }
        .padding(16)
    }
}

/// The bubble beside the notch: music beside the agents face (one source, two sources),
/// and an agent beside the media face.
private struct BubbleGallery: View {
    let slots: [NowPlayingSlot]

    private var lead: AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: .claudeCode, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func row(_ bubble: SideBubble.Content, _ face: some View) -> some View {
        HStack(spacing: IslandLayout.bubbleGap) {
            SideBubble(content: bubble, diameter: 28)
            face
                .frame(width: 272, height: 32)
                .background(
                    .black,
                    in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            row(.media(front: slots[0].info, behind: nil), AgentNotchFace(row: lead, notchWidth: 200))
            row(
                .media(front: slots[0].info, behind: slots[1].info),
                AgentNotchFace(row: lead, notchWidth: 200))
            row(.agent(lead), CollapsedContent(info: slots[0].info, behind: slots[1].info, notchWidth: 200))
        }
        .padding(.leading, 24)
        .padding(16)
    }
}

/// The files bubble right of the notch, placed by the island's own layout: one file, seven of
/// three kinds, the demo shelf beside the agents' wings with the music bubble on the left, and
/// more than 99 beside the media wings.
private struct FilesBubbleGallery: View {
    private enum Face { case none, agents, media }

    let shelf: FileShelf
    let slots: [NowPlayingSlot]

    /// A 200 × 32 camera housing in the middle of a row as wide as the render.
    private static let notch = CGRect(x: 110, y: 0, width: 200, height: 32)
    private static let row = CGSize(width: 420, height: 34)

    private var lead: AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: .claudeCode, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func row(_ face: Face, count: Int, kinds: [FileKind], leftBubble: Bool = false) -> some View {
        let wings = face != .none
        let island = IslandLayout.frame(
            phase: .collapsed, notch: Self.notch, screenSize: Self.row, showsWings: wings)
        let files = IslandLayout.filesBubbleFrame(
            notch: Self.notch, screenSize: Self.row, showsWings: wings)
        let left = IslandLayout.bubbleFrame(notch: Self.notch, screenSize: Self.row)
        return ZStack(alignment: .topLeading) {
            if leftBubble {
                SideBubble(content: .media(front: slots[0].info, behind: slots[1].info), diameter: left.width)
                    .offset(x: left.minX, y: left.minY)
            }
            FilesBubble(count: count, kinds: kinds, diameter: files.width)
                .offset(x: files.minX, y: files.minY)
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(.black)
                .overlay { content(face).padding(.bottom, IslandLayout.notchLip) }
                .frame(width: island.width, height: island.height)
                .offset(x: island.minX, y: island.minY)
        }
        .frame(width: Self.row.width, height: Self.row.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ face: Face) -> some View {
        switch face {
        case .none: EmptyView()
        case .agents: AgentNotchFace(row: lead, notchWidth: Self.notch.width)
        case .media: CollapsedContent(info: slots[0].info, notchWidth: Self.notch.width)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            row(.none, count: 1, kinds: [.image])
            row(.none, count: 7, kinds: [.pdf, .image, .document])
            row(.agents, count: shelf.count, kinds: shelf.bubbleKinds, leftBubble: true)
            row(.media, count: 128, kinds: [.video, .audio])
        }
        .padding(.vertical, 16)
    }
}

/// The tab glyphs: large on their grid, in pixels as a 2x screen draws them, at their real
/// size selected and not, and in the real strip with each tab selected and with the pip.
private struct TabGlyphGallery: View {
    private static let large: CGFloat = TabGlyphOutline.grid * 8

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
    }

    /// The glyph as a 2x backing draws it, enlarged without smoothing so each pixel shows.
    private func pixels(_ tab: IslandTab) -> some View {
        let renderer = ImageRenderer(content: TabGlyph(tab: tab).foregroundStyle(.white))
        renderer.scale = 2
        return Group {
            if let image = renderer.cgImage {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
        }
        .frame(width: Self.large / 2, height: Self.large / 2)
        .background(.white.opacity(0.06))
    }

    /// The grid, a line per point, behind the large drawing.
    private var grid: some View {
        Path { path in
            for index in 0...Int(TabGlyphOutline.grid) {
                let at = CGFloat(index) * Self.large / TabGlyphOutline.grid
                path.move(to: CGPoint(x: at, y: 0))
                path.addLine(to: CGPoint(x: at, y: Self.large))
                path.move(to: CGPoint(x: 0, y: at))
                path.addLine(to: CGPoint(x: Self.large, y: at))
            }
        }
        .stroke(.white.opacity(0.1), lineWidth: 0.5)
    }

    private func strip(_ selected: IslandTab, attention: AgentAttention = .none) -> some View {
        TabStrip(order: TabOrder.default, selected: selected, attention: attention) { _ in }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 26) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    VStack(alignment: .leading, spacing: 6) {
                        caption(tab.title)
                        HStack(alignment: .top, spacing: 10) {
                            TabGlyph(tab: tab, size: Self.large)
                                .foregroundStyle(.white)
                                .background(grid)
                            VStack(spacing: 12) {
                                pixels(tab)
                                HStack(spacing: 10) {
                                    TabGlyph(tab: tab).foregroundStyle(.white)
                                    TabGlyph(tab: tab).foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 22) {
                ForEach(IslandTab.allCases, id: \.self) { strip($0) }
                strip(.media, attention: .needsInput)
                strip(.files, attention: .finished)
                // Three times larger, to weigh the glyphs against each other. The strip is
                // three 28-point buttons 2 apart: 88 points wide.
                strip(.agents)
                    .scaleEffect(3, anchor: .leading)
                    .frame(width: 88 * 3, height: 22 * 3, alignment: .leading)
            }
        }
        .padding(18)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The finish seal at moments of its run.
private struct SealGallery: View {
    private static let times: [TimeInterval] = [0, 0.2, 0.45, 0.6, 0.75, 0.95, 1.5]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Self.times, id: \.self) { time in
                VStack(spacing: 10) {
                    FinishSeal(tool: .claudeCode, size: 48, frozenAt: time)
                        .frame(width: 64, height: 64)
                    FinishSeal(tool: .codex, size: 24, frozenAt: time)
                    Text(String(format: "%.2f s", time))
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The light of a working agent: at the notch at its dimmest and at its brightest, for a
/// second tool, then a capsule docked at the bottom and strips docked right and left, each
/// drawn still (1.2 s in) and as the live layers at rest (`at: nil`) right beside or under
/// it. The last notch is live too. Compare the pairs: the side, the direction of the fade
/// and where the line lies must agree.
private struct WorkingAuroraGallery: View {
    private func row(_ tool: AgentTool) -> AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: tool, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func island(
        _ anchor: IslandAnchor, _ size: CGSize, tool: AgentTool, at time: TimeInterval?,
        @ViewBuilder face: () -> some View
    ) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        let edge = WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: IslandLayout.isSideDocked(anchor))
        let margin = WorkingAurora.depth + 4
        let frame = CGRect(x: margin, y: margin, width: size.width, height: size.height)
        let band = WorkingAurora.band(island: frame, edge: edge)
        return ZStack(alignment: .topLeading) {
            WorkingAuroraLight(tool: tool, edge: edge, frozenAt: time)
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
            shape.fill(.black)
                .overlay { face() }
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .offset(x: frame.minX, y: frame.minY)
        }
        .frame(width: size.width + 2 * margin, height: size.height + 2 * margin, alignment: .topLeading)
    }

    private func notch(_ tool: AgentTool, at time: TimeInterval?) -> some View {
        island(.notch, CGSize(width: 272, height: 32 + IslandLayout.notchLip), tool: tool, at: time) {
            AgentNotchFace(row: row(tool), notchWidth: 200)
                .padding(.bottom, IslandLayout.notchLip)
        }
    }

    /// The capsule docked at the bottom of the screen.
    private func capsule(at time: TimeInterval?) -> some View {
        island(.edge(.bottom, fraction: 0.5), CGSize(width: 200, height: 36), tool: .codex, at: time) {
            AgentFloatingFace(row: row(.codex))
        }
    }

    /// The strip docked at `side` of the screen.
    private func strip(_ side: ScreenEdge, at time: TimeInterval?) -> some View {
        island(.edge(side, fraction: 0.5), CGSize(width: 36, height: 170), tool: .claudeCode, at: time) {
            AgentSideFace(row: row(.claudeCode))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                // Dimmest, brightest, and a quarter of a run on.
                notch(.claudeCode, at: 0)
                notch(.claudeCode, at: WorkingAurora.breathPeriod / 2)
                notch(.claudeCode, at: WorkingAurora.flowPeriod / 4)
                notch(.codex, at: WorkingAurora.breathPeriod / 2)
                capsule(at: 1.2)
                capsule(at: nil)
                notch(.claudeCode, at: nil)
            }
            // Each strip: still, then live layers at rest.
            HStack(alignment: .top, spacing: 8) {
                strip(.right, at: 1.2)
                strip(.right, at: nil)
                strip(.left, at: 1.2)
                strip(.left, at: nil)
            }
        }
        .padding(16)
    }
}

#endif
