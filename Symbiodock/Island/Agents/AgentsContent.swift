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
