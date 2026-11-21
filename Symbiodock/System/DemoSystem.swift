#if DEBUG
import Foundation
import SymbiodockCore

/// Fixed measures for looking at the System tab without measuring:
/// `open --env SYMBIODOCK_DEMO_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app`.
/// `1` is a calm Mac, `hot` a busy and warm one, `scanning` a scan in flight, `denied` a scan
/// macOS kept back. The tab does not open by itself: click it.
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
        func device(_ last: UInt8, _ name: String? = nil, _ kind: LANDevice.Kind = .other) -> LANDevice {
            LANDevice(address: LANAddress(192, 168, 1, last), name: name, kind: kind)
        }
        let everyone = [
            device(1, nil, .router), device(104, nil, .thisMac), device(101, "iPad"), device(100, "iPhone"),
            device(107, "Living Room TV"), device(110, "Printer"), device(102),
        ]
        // Without a scan the Mac knows only whom it has talked to.
        state.setLANDevices(set == "1" || set == "hot" ? everyone : Array(everyone.prefix(3)), canScan: true)
        if set == "scanning" || set == "denied" { state.requestLANScan() }
        if set == "denied" { state.finishLANScan(blocked: true) }
    }
}

/// `SYMBIODOCK_PRINT_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
/// prints four measures a second apart and quits, without building the island. With `loop` it
/// runs the coordinator against an island state of its own, opens and closes the System tab
/// on it, and prints how many measures arrived in each stretch: none may arrive while the tab
/// is not shown.
@MainActor
enum SystemHook {
    /// True when the hook took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        guard let mode = ProcessInfo.processInfo.environment["SYMBIODOCK_PRINT_SYSTEM"] else { return false }
        if mode == "loop" {
            checkLoop()
            return true
        }
        Task {
            let reader = SystemReader()
            var meter = SystemMeter()
            for _ in 0..<5 {
                let started = Date()
                let reading = await reader.read(withTemperatures: true)
                let cost = Int(Date().timeIntervalSince(started) * 1_000_000)
                if let snapshot = meter.take(reading) {
                    let memory = snapshot.memory.map {
                        "\(SystemLabels.gigabytes($0.used)) / \(SystemLabels.wholeGigabytes($0.total)) GB"
                    } ?? SystemLabels.missing
                    let down = snapshot.network.map { SystemLabels.rate($0.down) } ?? SystemLabels.missing
                    let up = snapshot.network.map { SystemLabels.rate($0.up) } ?? SystemLabels.missing
                    print(
                        "cpu \(SystemLabels.percent(snapshot.cpu)) \(SystemLabels.degrees(snapshot.temperatures.cpu))",
                        "| gpu \(SystemLabels.percent(snapshot.gpu)) \(SystemLabels.degrees(snapshot.temperatures.gpu))",
                        "| ram \(memory) | down \(down) up \(up)",
                        "| online \(snapshot.isOnline) | read \(cost) µs")
                }
                try? await Task.sleep(for: .seconds(1))
            }
            exit(0)
        }
        return true
    }

    /// Counts the measures the coordinator hands over.
    private final class Tally {
        var count = 0
    }

    private static func scanName(_ scan: LANScanState) -> String {
        switch scan {
        case .idle: "idle"
        case .scanning: "scanning"
        case .blocked: "blocked"
        }
    }

    private static func checkLoop() {
        Task {
            let state = IslandState()
            let tally = Tally()
            let lists = Tally()
            let coordinator = SystemCoordinator(
                isWatching: { state.phase == .expanded && state.selectedTab == .system },
                isScanRequested: { state.lanScan == .scanning },
                onUpdate: { snapshot, history in
                    tally.count += 1
                    state.setSystem(snapshot, history: history)
                },
                onDevices: { devices, canScan in
                    lists.count += 1
                    state.setLANDevices(devices, canScan: canScan)
                },
                onScanEnd: { state.finishLANScan(blocked: $0) })
            coordinator.start()
            @MainActor func stretch(_ name: String, seconds: Int) async {
                let before = tally.count
                try? await Task.sleep(for: .seconds(seconds))
                let cpu = SystemLabels.percent(state.system?.cpu)
                print("\(name), \(seconds) s: \(tally.count - before) measures, cpu \(cpu), graph \(state.networkHistory.samples.count), \(lists.count) device lists, \(state.lanDevices.count) devices, can scan \(state.canScanLAN), scan \(scanName(state.lanScan))")
            }
            await stretch("island closed", seconds: 3)
            state.setHovering(true)
            await stretch("open on \(state.selectedTab.rawValue)", seconds: 3)
            state.selectTab(.system)
            await stretch("System tab shown", seconds: 7)
            state.selectTab(.media)
            await stretch("another tab", seconds: 5)
            state.selectTab(.system)
            await stretch("System tab again", seconds: 5)
            state.setHovering(false)
            await stretch("island closed", seconds: 5)
            coordinator.stop()
            exit(0)
        }
    }
}
#endif
