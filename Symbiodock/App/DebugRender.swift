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
        write(StatusMarkGallery(), size: CGSize(width: 640, height: 150), named: "status-marks", to: directory)
        write(PetGallery(), size: CGSize(width: 800, height: 380), named: "pets", to: directory)
        for (name, tab) in [("expanded-agents", IslandTab.agents), ("expanded-media", .media)] {
            let state = IslandState()
            DemoAgents.apply("1", to: state)
            state.setHovering(true)
            state.selectTab(tab)
            write(
                ExpandedPreview(state: state), size: CGSize(width: 640, height: 190),
                named: name, to: directory)
        }
        let empty = IslandState()
        empty.setHovering(true)
        empty.selectTab(.agents)
        write(
            ExpandedPreview(state: empty), size: CGSize(width: 640, height: 190),
            named: "expanded-agents-empty", to: directory)
        let branches = IslandState()
        DemoAgents.apply("branches", to: branches)
        branches.setHovering(true)
        branches.selectTab(.agents)
        write(
            ExpandedPreview(state: branches), size: CGSize(width: 640, height: 190),
            named: "expanded-agents-branches", to: directory)
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
        ("compacting", .compacting, 0.3),
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

/// The open island as it is at the notch: 600 × 150, with a 200 × 32 camera housing.
private struct ExpandedPreview: View {
    let state: IslandState

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        ExpandedIsland(
            state: state,
            metrics: ExpandedHeaderMetrics(height: 32, leading: 200, gap: 200, trailing: 200),
            onCommand: { _ in }, onOpenSession: { _ in })
            .frame(width: 600, height: 150)
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
