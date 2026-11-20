import SwiftUI
import SymbiodockCore

/// The collapsed island speaking for the agents at the notch: the lead session's pet in
/// the left wing, its state in the right wing.
struct AgentNotchFace: View {
    let row: AgentRow
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            AgentFacePet(row: row)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            AgentStatusMark(state: row.state, tool: row.session.tool)
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
                AgentFacePet(row: row)
                Text(row.session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                AgentStatusMark(state: row.isSettled ? .idle : row.state, tool: row.session.tool)
            } else {
                // The Agents tab's prompt, as wide as the symbol it replaced so the text beside
                // it stays where it was.
                TabGlyph(tab: .agents)
                    .frame(width: 12.5)
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
                AgentFacePet(row: row)
                RotatedLine(text: row.session.title)
                    .foregroundStyle(.white)
                AgentStatusMark(state: row.isSettled ? .idle : row.state, tool: row.session.tool)
            } else {
                TabGlyph(tab: .agents)
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
enum AgentFaceLabel {
    static func text(for row: AgentRow?) -> String {
        guard let row else { return "No agents running" }
        let state: String = switch row.state {
        case .needsInput: "Needs input"
        case .working: "Working"
        case .compacting: "Compacting"
        case .finished: "Finished"
        case .running: "Running"
        case .idle: "Idle"
        }
        return "\(row.session.tool.displayName), \(row.session.title), \(state)"
    }
}

/// The pet on a collapsed face. A finish that has not settled shows its seal in its place;
/// a new finish starts a new seal.
struct AgentFacePet: View {
    let row: AgentRow
    var size: CGFloat = 24

    var body: some View {
        if row.state == .finished, !row.isSettled {
            FinishSeal(tool: row.session.tool, size: size)
                .id(row.id)
        } else {
            // A settled finish has ended its mark: the plain pet, quiet.
            AgentPet(tool: row.session.tool, state: row.isSettled ? .idle : row.state, size: size)
        }
    }
}
