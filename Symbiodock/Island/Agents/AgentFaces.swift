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
