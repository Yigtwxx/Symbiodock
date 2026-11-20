import Foundation

/// One working sub-agent as it circles the working mark of a collapsed face.
public struct AgentSatellite: Identifiable, Equatable, Sendable {
    /// The sub-agent's id.
    public let id: String
    /// Seconds for one turn round the mark.
    public let period: TimeInterval
    /// Where on the circle it is at time 0: a share of a turn, 0..<1, clockwise from the top.
    public let phase: Double
    /// Which of its tool's light colours it has, `0..<AgentSatellites.toneCount`.
    public let tone: Int

    public init(id: String, period: TimeInterval, phase: Double, tone: Int) {
        self.id = id
        self.period = period
        self.phase = phase
        self.tone = tone
    }
}

/// Which sub-agents circle a session's working mark, and how.
public enum AgentSatellites {
    /// The most satellites round one mark; further sub-agents are not shown.
    public static let maximum = 5
    /// Seconds for one turn: each satellite has its own, so they never move as one.
    public static let periodRange: ClosedRange<TimeInterval> = 2.3...4.3
    /// How many light colours a tool has to give.
    public static let toneCount = 4

    /// The working sub-agents of a session that works: oldest first, at most `maximum`.
    /// A session that waits, compacts, has finished or idles has none.
    public static func orbiters(for subagents: [AgentSubagent], state: AgentRowState) -> [AgentSatellite] {
        guard state == .working else { return [] }
        var taken = Set<Int>()
        return subagents
            .filter { !$0.isFinished }
            .sorted { ($0.since, $0.id) < ($1.since, $1.id) }
            .prefix(maximum)
            .map { subagent in
                // Its own tone unless one shown before it has it; then the next free one.
                var tone = AgentBranches.tone(of: subagent.id, count: toneCount)
                if taken.count < toneCount {
                    while taken.contains(tone) { tone = (tone + 1) % toneCount }
                }
                taken.insert(tone)
                return AgentSatellite(
                    id: subagent.id, period: period(of: subagent.id), phase: phase(of: subagent.id), tone: tone)
            }
    }

    /// A sub-agent's time for one turn, from its id: the same in every run.
    public static func period(of id: String) -> TimeInterval {
        periodRange.lowerBound + (periodRange.upperBound - periodRange.lowerBound) * share(of: id, salt: "period")
    }

    /// Where a sub-agent starts on its circle, from its id: 0..<1 of a turn.
    public static func phase(of id: String) -> Double {
        share(of: id, salt: "phase") * 0.9999
    }

    /// Where `satellite` is at `time`: a share of a turn, 0..<1, clockwise from the top.
    public static func turn(of satellite: AgentSatellite, at time: TimeInterval) -> Double {
        let turn = (satellite.phase + time / satellite.period).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }

    /// Where satellite `index` of `count` stands when nothing moves: evenly round the circle.
    public static func stillTurn(index: Int, count: Int) -> Double {
        count > 0 ? Double(index) / Double(count) : 0
    }

    /// A number 0...1 from an id and a salt: FNV-1a, so the same in every run.
    private static func share(of id: String, salt: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(salt):\(id)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 10_000) / 9_999
    }
}
