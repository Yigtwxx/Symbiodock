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
        write(PetGallery(), size: CGSize(width: 700, height: 300), named: "pets", to: directory)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ForEach(AgentTool.allCases, id: \.self) { tool in
                    VStack(spacing: 8) {
                        AgentPet(tool: tool, size: 60, frozenAt: 0)
                        HStack(spacing: 8) {
                            AgentPet(tool: tool, size: 30, frozenAt: 0)
                            AgentPet(tool: tool, size: 18, frozenAt: 0)
                        }
                        Text(tool.displayName).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(width: 76)
                }
            }
            HStack(spacing: 18) {
                Text("working").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).frame(width: 44)
                ForEach([0.0, 0.4, 0.8], id: \.self) { time in
                    AgentPet(tool: .claudeCode, state: .working, size: 40, frozenAt: time)
                    AgentPet(tool: .codex, state: .working, size: 40, frozenAt: time)
                }
            }
            HStack(spacing: 18) {
                Text("states").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).frame(width: 44)
                AgentPet(tool: .claudeCode, state: .needsInput(prompt: nil), size: 40, frozenAt: 0.15)
                AgentPet(tool: .claudeCode, state: .finished, size: 40, frozenAt: 0)
                AgentPet(tool: .claudeCode, state: .running, size: 40, frozenAt: 0)
                AgentPet(tool: .claudeCode, state: .idle, size: 40, frozenAt: 0)
            }
        }
        .padding(16)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
#endif
