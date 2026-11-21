#if DEBUG
import Foundation
import SymbiodockCore

/// Fixed measures for looking at the System tab without measuring:
/// `open --env SYMBIODOCK_DEMO_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app`.
/// `1` is a calm Mac, `hot` a busy and warm one. The tab does not open by itself: click it.
@MainActor
enum DemoSystem {
    static var requested: String? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_SYSTEM"]
    }

    static func apply(_ set: String, to state: IslandState) {
        let hot = set == "hot"
        var history = NetworkHistory()
        for index in 0..<NetworkHistory.capacity {
            let step = Double(index)
            let wave = abs(sin(step * 0.9)) * 0.7 + abs(sin(step * 0.37)) * 0.3
            history.append(
                NetworkSpeed(
                    down: (hot ? 41_400_000 : 1_700_000) * (0.25 + 0.75 * wave),
                    up: (hot ? 5_500_000 : 156_000) * (0.4 + 0.6 * abs(cos(step * 0.5)))))
        }
        let gigabyte = 1_073_741_824.0
        state.setSystem(
            SystemSnapshot(
                cpu: hot ? 0.93 : 0.31, gpu: hot ? 0.64 : 0.24,
                memory: MemoryUse(used: UInt64((hot ? 41.1 : 18.5) * gigabyte), total: UInt64(48 * gigabyte)),
                temperatures: Temperatures(cpu: hot ? 96 : 45, gpu: hot ? 83 : 46),
                network: history.samples.last, isOnline: true),
            history: history)
    }
}
#endif
