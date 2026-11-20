import SwiftUI
import SymbiodockCore

/// The Agents tab: the sessions one under the other, two at a time, or an idle message.
/// A session's subagents hang below its row as branches.
struct AgentsContent: View {
    let rows: [AgentRow]
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat
    let onOpen: (AgentSession) -> Void

    /// How many sessions the viewport is sized for; the rest are reached by scrolling.
    private static let visibleRows = 2
    private static let rowSpacing: CGFloat = 4
    /// Kept free below the list.
    private static let bottomMargin: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            Group {
                if rows.isEmpty {
                    idle
                } else {
                    list(available: proxy.size.height - Self.bottomMargin)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.top, topInset)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            // The Agents tab's prompt, drawn about as large as the symbol it replaced, in that
            // symbol's 23 × 26 box so the line below stays where it was.
            TabGlyph(tab: .agents, size: 24)
                .frame(width: 23, height: 26)
                .foregroundStyle(.white.opacity(0.35))
            Text("No agents running")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// The blocks' heights with the spacing between them.
    private func height(of rows: some Collection<AgentRow>) -> CGFloat {
        let blocks = rows.reduce(0) { $0 + AgentRowView.height(of: $1) }
        return blocks + CGFloat(max(rows.count - 1, 0)) * Self.rowSpacing
    }

    /// As tall as the first two blocks, but never taller than the room below the header,
    /// so one or two blocks sit centred and a tall block is scrolled.
    private func list(available: CGFloat) -> some View {
        let viewport = min(height(of: rows.prefix(Self.visibleRows)), max(available, AgentRowView.rowHeight))
        let overflows = height(of: rows) > viewport + 0.5
        // The labels count minutes; they are redrawn on their own now and then.
        return TimelineView(.periodic(from: .now, by: 20)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(rows) { row in
                        AgentRowView(row: row, now: context.date, onOpen: onOpen)
                    }
                }
                .scrollTargetLayout()
            }
            // The list comes to rest on a session, never between two.
            .scrollTargetBehavior(.viewAligned)
            .frame(height: viewport)
            .mask {
                // Fading out at the lower edge says that the list goes on.
                if overflows {
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
    static let rowHeight: CGFloat = 46

    /// The row and the branches below it.
    static func height(of row: AgentRow) -> CGFloat {
        rowHeight + AgentBranchLines.height(of: row.branches)
    }

    let row: AgentRow
    let now: Date
    let onOpen: (AgentSession) -> Void

    var body: some View {
        if row.session.hostAppPID != nil {
            Button {
                onOpen(row.session)
            } label: {
                block
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Brings its app to the front")
        } else {
            block
        }
    }

    /// One scroll target: the row and its branches.
    private var block: some View {
        VStack(spacing: 0) {
            content
            if !row.branches.isEmpty {
                AgentBranchLines(branches: row.branches, tool: row.session.tool, now: now)
            }
        }
        .contentShape(Rectangle())
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
        case .compacting: AgentPalette.compacting
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
            // The status text beside it already speaks; the mark would repeat it.
            AgentStatusMark(state: row.state, tool: row.session.tool)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
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

/// A session's subagents below its row, joined to its pet by a thin line, like a fork.
/// Nothing in it moves: the times change with the list's periodic redraw.
private struct AgentBranchLines: View {
    static let lineHeight: CGFloat = 16
    /// Below the last line, so that the next row does not touch it.
    static let bottomPadding: CGFloat = 4
    /// The connector runs under the pet's centre: the row's padding and half the pet.
    private static let connectorX: CGFloat = 10 + 18
    private static let tick: CGFloat = 8
    /// The parent pet's colours the dots take: its first, middle and last.
    private static let toneCount = 3
    private static let dotSize: CGFloat = 4
    /// The pet (36 pt) sits in the 46 pt row, so its bottom is this far above the first
    /// line; the first vertical starts that much higher to reach it.
    private static let petGap: CGFloat = (46 - 36) / 2
    /// The trailing text ends where the row's label ends: the row's padding, the status
    /// mark and the spacing before it.
    private static let trailingInset: CGFloat = 10 + 14 + 10

    static func height(of branches: [AgentBranch]) -> CGFloat {
        branches.isEmpty ? 0 : CGFloat(branches.count) * lineHeight + bottomPadding
    }

    let branches: [AgentBranch]
    let tool: AgentTool
    let now: Date

    var body: some View {
        let tones = AgentBranches.tones(for: branches, count: Self.toneCount)
        VStack(spacing: 0) {
            ForEach(Array(zip(branches, tones)), id: \.0.id) { branch, tone in
                line(branch, tone: tone)
            }
        }
        .overlay(alignment: .topLeading) { trunk(tones: tones) }
        .padding(.bottom, Self.bottomPadding)
    }

    /// The vertical from under the pet down to the last line's middle (`└`). Its colour runs
    /// through the lines' tones, so it meets each tick in the tick's own colour; it fades to
    /// the plain line where `+N more` closes the list.
    private func trunk(tones: [Int?]) -> some View {
        let length = Self.petGap + CGFloat(branches.count - 1) * Self.lineHeight + Self.lineHeight / 2
        let stops = zip(branches, tones).enumerated().map { index, pair in
            Gradient.Stop(
                color: tickColor(pair.0, tone: pair.1),
                location: (Self.petGap + (CGFloat(index) + 0.5) * Self.lineHeight) / length)
        }
        return Rectangle()
            .fill(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
            .frame(width: 1, height: length)
            .offset(x: Self.connectorX - 0.5, y: -Self.petGap)
            .accessibilityHidden(true)
    }

    private func line(_ branch: AgentBranch, tone: Int?) -> some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Tick(x: Self.connectorX, length: Self.tick)
                    .stroke(tickColor(branch, tone: tone), lineWidth: 1)
                if let tone, case .subagent(let subagent) = branch {
                    Circle()
                        .fill(tint(tone, finished: subagent.isFinished))
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .position(x: Self.connectorX + Self.tick, y: Self.lineHeight / 2)
                }
            }
            .frame(width: Self.connectorX + Self.tick + Self.dotSize / 2, height: Self.lineHeight)
            label(branch)
        }
        .padding(.trailing, Self.trailingInset)
        .frame(height: Self.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentLabels.branchDescription(branch, now: now))
    }

    /// A tone of the parent pet's colours; dimmer once the subagent is done.
    private func tint(_ tone: Int, finished: Bool) -> Color {
        let position = Double(tone) / Double(Self.toneCount - 1)
        return AgentPalette.tint(for: tool, across: position).opacity(finished ? 0.45 : 0.9)
    }

    private func tickColor(_ branch: AgentBranch, tone: Int?) -> Color {
        guard let tone, case .subagent(let subagent) = branch else { return .white.opacity(0.22) }
        return tint(tone, finished: subagent.isFinished)
    }

    @ViewBuilder
    private func label(_ branch: AgentBranch) -> some View {
        switch branch {
        case .subagent(let subagent):
            Text(subagent.title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(subagent.isFinished ? 0.4 : 0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if subagent.isFinished {
                HStack(spacing: 3) {
                    Text(AgentLabels.branchStatus(subagent, now: now))
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AgentPalette.mint)
                .fixedSize()
            } else {
                Text(AgentLabels.branchStatus(subagent, now: now))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
        case .more(let count):
            Text("+\(count) more")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }
}

/// The short line from the vertical into a branch (`─`).
private struct Tick: Shape {
    let x: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: x + length, y: rect.midY))
        return path
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
