# System Tab, Part A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fourth tab, `System`, that shows this Mac's CPU, GPU and RAM use, the CPU and GPU temperature, and the network speed with a one-minute graph, measured only while the tab is on screen.

**Architecture:** Pure arithmetic lives in `Packages/SymbiodockCore` and is tested with `swift test`: usage from tick counters, speed from byte counters, the median of temperature keys, the labels, and `SystemMeter`, which turns raw readings into a `SystemSnapshot`. The app target reads the system (`host_statistics`, IOKit, `AppleSMC`, `sysctl`) inside one actor, off the main thread. `SystemCoordinator` observes `IslandState` and runs the loop only while the open island shows the System tab; results go into `IslandState`, which the view reads.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Core Animation, IOKit, SystemConfiguration, Swift Testing, XcodeGen.

Spec: `docs/superpowers/specs/2026-11-21-system-tab-design.md`. Read it first. This plan is Part A only: the devices on the network (Part B) need a macOS permission and get their own plan later. In Part A the `Devices` panel is drawn with its caption and a dash.

## Global Constraints

- Minimum macOS 14.0. Swift 6 strict concurrency, no extra flags.
- `SymbiodockCore` imports only Foundation (and CoreGraphics, Observation, `os` where it already does). No AppKit, SwiftUI or IOKit there.
- No view may redraw frame by frame at rest (see the comment at the top of `Symbiodock/Island/LayerAnimation.swift`). The bars change through Core Animation; texts and the graph change only when a new sample arrives (every 2 s).
- Nothing is measured while the System tab is not on screen.
- No hook, no `sudo`, no new third-party dependency, no macOS permission prompt in Part A.
- Interface text is English. Code, identifiers and comments are English.
- Logs carry numbers and error codes only (`Logger(subsystem: "com.yigtwxx.Symbiodock", category: "system")`).
- Exact values from the spec: content insets 2 pt top (below the header), 16 pt sides, 14 pt bottom; column gap 10; `Network` panel 128 pt, `Devices` panel 164 pt; panels white 0.05 with corner radius 14; bar 6 pt high on a white 0.14 track, never shorter than 6 pt; temperature text turns `#FFD60A` at 80 °C and `#FF6B5E` at 95 °C; colours CPU `#2F7BFF`→`#5EE7FF`, GPU `#A45CFF`→`#FF7EDB`, RAM `#34D17A`→`#C6F56B`, download `#7CF5C8` (area fades to `#2BD4A4`), upload `#FFB86B`.
- Plans are written without compiling the app. If code here does not compile, fix it while keeping the behaviour and the interfaces, and correct this plan in the same commit. (The system reads in Task 5 were compiled and run as a script in Swift 6 mode on 2026-11-21.)
- Verification after every task:
  - `swift test --package-path Packages/SymbiodockCore` passes (766 tests before this plan).
  - `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends with `** BUILD SUCCEEDED **`.
- Offscreen renders: `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock` writes PNG files and quits. Look at the files you changed with the Read tool.
- Commits: Conventional Commits, title at most 72 characters, imperative, body says why. Commit each task and push to `main` (`git push origin main`). End every commit message with:

```
Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BW1DAFBBz2zwgt57hNkzQK
```

## File Structure

| File | Responsibility |
|---|---|
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeasures.swift` (create) | Value types and the arithmetic: CPU ticks, memory pages, network counters |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/TemperatureKeys.swift` (create) | Which SMC keys are CPU or GPU, the median, the evenly spread subset |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemLabels.swift` (create) | `31%`, `45°`, `1.7 MB/s`, `18.5`, the temperature tier |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeter.swift` (create) | `SystemReading` → `SystemSnapshot`, `NetworkHistory` |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandTab.swift` (modify) | `case system`, default order |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (modify) | `system`, `networkHistory`, `setSystem(_:history:)` |
| `Symbiodock/Island/TabStrip.swift`, `TabGlyph.swift`, `ExpandedIsland.swift`, `IslandView.swift` (modify) | Title, chip glyph, content switch, bubble switch |
| `Symbiodock/Island/System/SystemContent.swift` (create) | The tab's page |
| `Symbiodock/Island/System/MeterBar.swift` (create) | The bar, as Core Animation layers |
| `Symbiodock/Island/System/SystemPalette.swift` (create) | The colours |
| `Symbiodock/System/DemoSystem.swift` (create) | `SYMBIODOCK_DEMO_SYSTEM`, `SYMBIODOCK_PRINT_SYSTEM` (Debug) |
| `Symbiodock/System/HostSampler.swift`, `GPUProbe.swift`, `SMCReader.swift`, `ThermalFallback.swift`, `NetworkCounterReader.swift` (create) | One system read each |
| `Symbiodock/System/SystemReader.swift` (create) | The actor that takes one whole reading |
| `Symbiodock/System/SystemCoordinator.swift` (create) | Runs the loop while the tab is on screen |
| `Symbiodock/App/AppDelegate.swift`, `DebugRender.swift` (modify) | Wiring, renders |
| `CLAUDE.md`, the spec (modify) | Status and what was measured |

---

### Task 1: The arithmetic

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeasures.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/System/TemperatureKeys.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemLabels.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemMeasuresTests.swift`, `TemperatureKeysTests.swift`, `SystemLabelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `CPUTicks(busy:total:)`, `CPUUsage.fraction(previous:current:) -> Double?`, `MemoryPages(internalPages:purgeable:wired:compressed:)`, `MemoryUse(used:total:)` with `.fraction`, `MemoryUsage.used(_:pageSize:) -> UInt64`, `NetworkCounters(interface:received:sent:)`, `NetworkSpeed(down:up:)`, `NetworkRate.maximumGap`, `NetworkRate.speed(previous:current:elapsed:) -> NetworkSpeed?`, `TemperatureSensor`, `TemperatureKeys.sensor(forKey:)`, `.validRange`, `.cpuLimit`, `.gpuLimit`, `.spread(_:limit:)`, `.typical(_:)`, `TemperatureTier`, `SystemLabels.missing`, `.percent(_:)`, `.degrees(_:)`, `.tier(_:)`, `.rate(_:)`, `.gigabytes(_:)`, `.wholeGigabytes(_:)`.

- [ ] **Step 1: Write the failing tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemMeasuresTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct SystemMeasuresTests {
    @Test func cpuUseIsTheBusyShareBetweenTwoReadings() {
        let fraction = CPUUsage.fraction(
            previous: CPUTicks(busy: 1_000, total: 10_000), current: CPUTicks(busy: 1_250, total: 11_000))
        #expect(fraction == 0.25)
    }

    @Test func cpuUseNeedsTwoReadingsThatAdvance() {
        let ticks = CPUTicks(busy: 1_000, total: 10_000)
        #expect(CPUUsage.fraction(previous: nil, current: ticks) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: nil) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: ticks) == nil)
        // The counters are 32-bit in the kernel and wrap.
        #expect(CPUUsage.fraction(previous: ticks, current: CPUTicks(busy: 10, total: 90)) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: CPUTicks(busy: 900, total: 12_000)) == nil)
    }

    @Test func cpuUseNeverPassesOne() {
        let fraction = CPUUsage.fraction(
            previous: CPUTicks(busy: 0, total: 100), current: CPUTicks(busy: 300, total: 200))
        #expect(fraction == 1)
    }

    @Test func usedMemoryIsAppWiredAndCompressed() {
        let pages = MemoryPages(internalPages: 1_000, purgeable: 100, wired: 200, compressed: 50)
        #expect(MemoryUsage.used(pages, pageSize: 16_384) == 1_150 * 16_384)
    }

    @Test func purgeableMemoryNeverMakesTheSumNegative() {
        let pages = MemoryPages(internalPages: 10, purgeable: 100, wired: 2, compressed: 1)
        #expect(MemoryUsage.used(pages, pageSize: 4_096) == 3 * 4_096)
    }

    @Test func memoryFractionIsUsedOverTotal() {
        #expect(MemoryUse(used: 12, total: 48).fraction == 0.25)
        #expect(MemoryUse(used: 60, total: 48).fraction == 1)
        #expect(MemoryUse(used: 5, total: 0).fraction == 0)
    }

    @Test func networkSpeedIsBytesPerSecond() {
        let speed = NetworkRate.speed(
            previous: NetworkCounters(interface: "en0", received: 1_000, sent: 500),
            current: NetworkCounters(interface: "en0", received: 5_000, sent: 1_500), elapsed: 2)
        #expect(speed == NetworkSpeed(down: 2_000, up: 500))
    }

    @Test func networkSpeedIsUnknownAcrossAGapAResetOrAnotherInterface() {
        let before = NetworkCounters(interface: "en0", received: 1_000, sent: 500)
        let after = NetworkCounters(interface: "en0", received: 5_000, sent: 1_500)
        #expect(NetworkRate.speed(previous: nil, current: after, elapsed: 2) == nil)
        #expect(NetworkRate.speed(previous: before, current: nil, elapsed: 2) == nil)
        #expect(NetworkRate.speed(previous: before, current: after, elapsed: 0) == nil)
        // The Mac slept in between.
        #expect(NetworkRate.speed(previous: before, current: after, elapsed: 10.5) == nil)
        #expect(NetworkRate.speed(previous: after, current: before, elapsed: 2) == nil)
        let other = NetworkCounters(interface: "en7", received: 9_000, sent: 9_000)
        #expect(NetworkRate.speed(previous: before, current: other, elapsed: 2) == nil)
    }
}
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/TemperatureKeysTests.swift`:

```swift
import Testing
@testable import SymbiodockCore

struct TemperatureKeysTests {
    @Test func keysAreSortedIntoProcessorAndGraphics() {
        #expect(TemperatureKeys.sensor(forKey: "Tp0D") == .cpu)
        #expect(TemperatureKeys.sensor(forKey: "Te05") == .cpu)
        #expect(TemperatureKeys.sensor(forKey: "Tg0K") == .gpu)
    }

    @Test func otherKeysAreNotTemperaturesOfTheChip() {
        // Battery, palm rest, SSD, and names of the wrong length.
        for name in ["TB0T", "Ts0P", "TH0a", "TG0P", "Tp", "Tp0DD", "FNum", ""] {
            #expect(TemperatureKeys.sensor(forKey: name) == nil)
        }
    }

    @Test func theTypicalValueIsTheMedian() {
        #expect(TemperatureKeys.typical([40, 44, 72]) == 44)
        #expect(TemperatureKeys.typical([40, 44, 46, 72]) == 45)
        #expect(TemperatureKeys.typical([51.5]) == 51.5)
    }

    /// Recorded on an M4 Pro: most keys do not read below 40, a few hold a peak.
    @Test func floorsAndHeldPeaksDoNotPullTheMedian() {
        let values: [Double] = [40, 40, 40, 40, 40, 41.2, 48.6, 60.8, 42.4, 72.2]
        #expect(TemperatureKeys.typical(values) == 40.6)
    }

    @Test func readingsOutsideTheRangeAreDropped() {
        #expect(TemperatureKeys.typical([-9201.1, 0, 44, 130, .nan]) == 44)
        #expect(TemperatureKeys.typical([0, 500]) == nil)
        #expect(TemperatureKeys.typical([]) == nil)
        #expect(TemperatureKeys.typical([10, 120]) == 65)
    }

    @Test func aSubsetIsSpreadEvenlyAndKeepsItsOrder() {
        #expect(TemperatureKeys.spread(Array(0..<10), limit: 5) == [0, 2, 4, 6, 8])
        #expect(TemperatureKeys.spread(Array(0..<7), limit: 3) == [0, 2, 4])
        #expect(TemperatureKeys.spread(["a", "b"], limit: 5) == ["a", "b"])
        #expect(TemperatureKeys.spread(["a", "b"], limit: 0) == [])
    }
}
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemLabelsTests.swift`:

```swift
import Testing
@testable import SymbiodockCore

struct SystemLabelsTests {
    @Test func percentIsWholeAndClamped() {
        #expect(SystemLabels.percent(0.314) == "31%")
        #expect(SystemLabels.percent(0.996) == "100%")
        #expect(SystemLabels.percent(1.7) == "100%")
        #expect(SystemLabels.percent(-0.2) == "0%")
        #expect(SystemLabels.percent(nil) == "—")
    }

    @Test func degreesAreWhole() {
        #expect(SystemLabels.degrees(44.6) == "45°")
        #expect(SystemLabels.degrees(nil) == "—")
    }

    @Test func temperatureTiersFollowTheShownNumber() {
        #expect(SystemLabels.tier(79.4) == .normal)
        #expect(SystemLabels.tier(79.5) == .warm)
        #expect(SystemLabels.tier(94.4) == .warm)
        #expect(SystemLabels.tier(94.5) == .hot)
        #expect(SystemLabels.tier(nil) == .normal)
    }

    @Test func ratesUseDecimalUnits() {
        #expect(SystemLabels.rate(0) == "0 KB/s")
        #expect(SystemLabels.rate(-5) == "0 KB/s")
        #expect(SystemLabels.rate(156_400) == "156 KB/s")
        #expect(SystemLabels.rate(999_400) == "999 KB/s")
        #expect(SystemLabels.rate(999_500) == "1.0 MB/s")
        #expect(SystemLabels.rate(1_740_000) == "1.7 MB/s")
        #expect(SystemLabels.rate(41_400_000) == "41.4 MB/s")
        #expect(SystemLabels.rate(1_260_000_000) == "1.3 GB/s")
    }

    @Test func memoryIsInBinaryGigabytes() {
        let gigabyte: UInt64 = 1_073_741_824
        #expect(SystemLabels.gigabytes(gigabyte * 37 / 2) == "18.5")
        #expect(SystemLabels.gigabytes(0) == "0.0")
        #expect(SystemLabels.wholeGigabytes(48 * gigabyte) == "48")
    }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -15`
Expected: the build fails with `cannot find 'CPUUsage' in scope` (and the other new names).

- [ ] **Step 3: Write the code**

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeasures.swift`:

```swift
import Foundation

/// The processor's tick counters since boot, summed over the cores.
public struct CPUTicks: Equatable, Sendable {
    /// Ticks spent working: user, system and nice.
    public var busy: UInt64
    /// All ticks, idle included.
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public enum CPUUsage {
    /// The share of the time between two readings the processor was busy, 0...1. Nil without
    /// two readings, and when the counters did not advance: the kernel's are 32-bit and wrap.
    public static func fraction(previous: CPUTicks?, current: CPUTicks?) -> Double? {
        guard let previous, let current, current.total > previous.total, current.busy >= previous.busy
        else { return nil }
        return min(1, Double(current.busy - previous.busy) / Double(current.total - previous.total))
    }
}

/// The page counts the kernel reports, as far as "memory used" needs them.
public struct MemoryPages: Equatable, Sendable {
    /// Anonymous memory: what apps allocated.
    public var internalPages: UInt64
    /// The part of it the system may take back at once.
    public var purgeable: UInt64
    public var wired: UInt64
    /// Pages the compressor itself occupies.
    public var compressed: UInt64

    public init(internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.internalPages = internalPages
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }
}

public struct MemoryUse: Equatable, Sendable {
    public var used: UInt64
    public var total: UInt64

    public init(used: UInt64, total: UInt64) {
        self.used = used
        self.total = total
    }

    /// 0...1; 0 while the total is unknown.
    public var fraction: Double {
        total > 0 ? min(1, Double(used) / Double(total)) : 0
    }
}

public enum MemoryUsage {
    /// Bytes in use as Activity Monitor counts them: app memory, wired and compressed.
    public static func used(_ pages: MemoryPages, pageSize: UInt64) -> UInt64 {
        let app = pages.internalPages > pages.purgeable ? pages.internalPages - pages.purgeable : 0
        return (app + pages.wired + pages.compressed) * pageSize
    }
}

/// The byte counters of one network interface since it came up.
public struct NetworkCounters: Equatable, Sendable {
    public var interface: String
    public var received: UInt64
    public var sent: UInt64

    public init(interface: String, received: UInt64, sent: UInt64) {
        self.interface = interface
        self.received = received
        self.sent = sent
    }
}

/// Bytes per second.
public struct NetworkSpeed: Equatable, Sendable {
    public var down: Double
    public var up: Double

    public init(down: Double, up: Double) {
        self.down = down
        self.up = up
    }
}

public enum NetworkRate {
    /// Two readings further apart than this are not compared: the Mac slept in between, and
    /// the average over the gap would say nothing about now.
    public static let maximumGap: TimeInterval = 10

    /// The speed between two readings of the same interface. Nil across a gap, when the
    /// counters went backwards (the interface came up again) or the interface changed.
    public static func speed(
        previous: NetworkCounters?, current: NetworkCounters?, elapsed: TimeInterval
    ) -> NetworkSpeed? {
        guard let previous, let current, previous.interface == current.interface,
              elapsed > 0, elapsed <= maximumGap,
              current.received >= previous.received, current.sent >= previous.sent
        else { return nil }
        return NetworkSpeed(
            down: Double(current.received - previous.received) / elapsed,
            up: Double(current.sent - previous.sent) / elapsed)
    }
}
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/TemperatureKeys.swift`:

```swift
import Foundation

public enum TemperatureSensor: Equatable, Sendable {
    case cpu
    case gpu
}

/// Which keys of the System Management Controller are temperatures of the chip, and how
/// many readings become one number.
///
/// Measured on an M4 Pro (2026-11-21): about 100 keys begin with `Tp` or `Te` (performance
/// and efficiency cores) and 22 with `Tg` (graphics). Most do not read below 40 °C and a few
/// hold a peak, so the median is taken, not the mean. Reading one key takes about 170 µs,
/// so only a spread subset is read each time. Other chips name their keys differently.
public enum TemperatureKeys {
    /// Readings outside are sensors that are absent or asleep.
    public static let validRange: ClosedRange<Double> = 10...120
    /// At most this many keys are read each time.
    public static let cpuLimit = 24
    public static let gpuLimit = 8

    public static func sensor(forKey name: String) -> TemperatureSensor? {
        guard name.utf8.count == 4 else { return nil }
        if name.hasPrefix("Tp") || name.hasPrefix("Te") { return .cpu }
        if name.hasPrefix("Tg") { return .gpu }
        return nil
    }

    /// At most `limit` of the items, evenly spread and in their order.
    public static func spread<Item>(_ items: [Item], limit: Int) -> [Item] {
        guard limit > 0 else { return [] }
        guard items.count > limit else { return items }
        return (0..<limit).map { items[$0 * items.count / limit] }
    }

    /// The median of the readings within the valid range; nil when there is none.
    public static func typical(_ values: [Double]) -> Double? {
        let valid = values.filter { validRange.contains($0) }.sorted()
        guard !valid.isEmpty else { return nil }
        let middle = valid.count / 2
        return valid.count % 2 == 1 ? valid[middle] : (valid[middle - 1] + valid[middle]) / 2
    }
}
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemLabels.swift`:

```swift
import Foundation

/// How warm a temperature reads: the colour of its number.
public enum TemperatureTier: Equatable, Sendable {
    case normal
    case warm
    case hot
}

/// The words and numbers of the System tab.
public enum SystemLabels {
    /// Shown for a value that could not be read.
    public static let missing = "—"

    private static let gigabyte = 1_073_741_824.0

    /// 0.314 → "31%".
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return missing }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// 44.6 → "45°".
    public static func degrees(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return missing }
        return "\(Int(celsius.rounded()))°"
    }

    /// Warm from 80 °C, hot from 95 °C, by the number that is shown.
    public static func tier(_ celsius: Double?) -> TemperatureTier {
        guard let celsius, celsius.isFinite else { return .normal }
        let shown = celsius.rounded()
        return shown >= 95 ? .hot : shown >= 80 ? .warm : .normal
    }

    /// Bytes per second in decimal units: "156 KB/s", "1.7 MB/s", "1.3 GB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        if value >= 999_950_000 { return String(format: "%.1f GB/s", value / 1_000_000_000) }
        if value >= 999_500 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return "\(Int((value / 1_000).rounded())) KB/s"
    }

    /// Memory in binary gigabytes with one decimal, as Activity Monitor shows it: "18.5".
    public static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / gigabyte)
    }

    /// The installed memory: "48".
    public static func wholeGigabytes(_ bytes: UInt64) -> String {
        "\(Int((Double(bytes) / gigabyte).rounded()))"
    }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: all tests pass (766 + 19 = 785).

If `floorsAndHeldPeaksDoNotPullTheMedian` fails by a rounding hair (`40.6` against `40.6000…1`), compare with a tolerance instead: `#expect(abs((TemperatureKeys.typical(values) ?? 0) - 40.6) < 0.0001)`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore/Sources/SymbiodockCore/System Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemMeasuresTests.swift Packages/SymbiodockCore/Tests/SymbiodockCoreTests/TemperatureKeysTests.swift Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemLabelsTests.swift
git commit -m "feat(core): add the arithmetic of the System tab" -m "Usage from tick counters, speed from byte counters, the median of the temperature keys and the labels are pure, so they are tested without reading the system."
git push origin main
```

(Add the two trailer lines from Global Constraints to every commit message.)

---

### Task 2: From readings to a snapshot

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeter.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (the property after `volumes`, about line 71; the method after `setVolume(_:for:)`, about line 387)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemMeterTests.swift`, `IslandStateTests.swift`

**Interfaces:**
- Consumes: Task 1's `CPUTicks`, `CPUUsage`, `MemoryUse`, `NetworkCounters`, `NetworkSpeed`, `NetworkRate`.
- Produces:
  - `Temperatures(cpu: Double? = nil, gpu: Double? = nil)`
  - `SystemReading(date:cpu:memory:gpu:temperatures:counters:)` — `cpu: CPUTicks?`, `memory: MemoryUse?`, `gpu: Double?`, `temperatures: Temperatures?` (nil: not read this time), `counters: NetworkCounters?` (nil: no network)
  - `SystemSnapshot(cpu:gpu:memory:temperatures:network:isOnline:)` — `cpu: Double?`, `gpu: Double?`, `memory: MemoryUse?`, `temperatures: Temperatures`, `network: NetworkSpeed?`, `isOnline: Bool`
  - `NetworkHistory`: `static let capacity = 30`, `samples: [NetworkSpeed]`, `mutating append(_:)`, `mutating reset()`, `scale: Double`, `downFractions: [Double]`, `upFractions: [Double]`
  - `SystemMeter`: `init()`, `mutating take(_ reading: SystemReading) -> SystemSnapshot?`, `history: NetworkHistory`
  - `IslandState.system: SystemSnapshot?`, `IslandState.networkHistory: NetworkHistory`, `IslandState.setSystem(_:history:)`

- [ ] **Step 1: Write the failing tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SystemMeterTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct SystemMeterTests {
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private func reading(
        at seconds: TimeInterval, busy: UInt64, total: UInt64, received: UInt64? = nil,
        temperatures: Temperatures? = nil
    ) -> SystemReading {
        SystemReading(
            date: start.addingTimeInterval(seconds), cpu: CPUTicks(busy: busy, total: total),
            memory: MemoryUse(used: 20, total: 48), gpu: 0.26, temperatures: temperatures,
            counters: received.map { NetworkCounters(interface: "en0", received: $0, sent: $0 / 10) })
    }

    @Test func theFirstReadingOnlyPrimesTheMeter() {
        var meter = SystemMeter()
        #expect(meter.take(reading(at: 0, busy: 100, total: 1_000, received: 5_000)) == nil)
        #expect(meter.history.samples.isEmpty)
    }

    @Test func theSecondReadingGivesUseAndSpeed() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 100, total: 1_000, received: 10_000))
        let snapshot = meter.take(reading(at: 2, busy: 400, total: 2_000, received: 14_000))
        #expect(snapshot?.cpu == 0.3)
        #expect(snapshot?.gpu == 0.26)
        #expect(snapshot?.memory == MemoryUse(used: 20, total: 48))
        #expect(snapshot?.network == NetworkSpeed(down: 2_000, up: 200))
        #expect(snapshot?.isOnline == true)
        #expect(meter.history.samples == [NetworkSpeed(down: 2_000, up: 200)])
    }

    @Test func temperaturesStayUntilTheyAreReadAgain() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, temperatures: Temperatures(cpu: 44, gpu: 37)))
        let second = meter.take(reading(at: 2, busy: 10, total: 200))
        #expect(second?.temperatures == Temperatures(cpu: 44, gpu: 37))
        let third = meter.take(reading(at: 4, busy: 20, total: 300, temperatures: Temperatures(cpu: 51, gpu: nil)))
        #expect(third?.temperatures == Temperatures(cpu: 51, gpu: nil))
    }

    @Test func aGapPrimesAgainAndEmptiesTheGraph() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 1_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 2_000))
        #expect(meter.history.samples.count == 1)
        // The tab was hidden, or the Mac slept.
        #expect(meter.take(reading(at: 60, busy: 500, total: 9_000, received: 900_000)) == nil)
        #expect(meter.history.samples.isEmpty)
        let after = meter.take(reading(at: 60.5, busy: 550, total: 9_100, received: 901_000))
        #expect(after?.cpu == 0.5)
        #expect(after?.network == NetworkSpeed(down: 2_000, up: 200))
    }

    @Test func aClockThatWentBackPrimesAgain() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 10, busy: 0, total: 100))
        #expect(meter.take(reading(at: 8, busy: 10, total: 200)) == nil)
    }

    @Test func withoutANetworkTheSnapshotIsOfflineAndTheGraphEmpties() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 1_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 2_000))
        let offline = meter.take(reading(at: 4, busy: 20, total: 300))
        #expect(offline?.isOnline == false)
        #expect(offline?.network == nil)
        #expect(offline?.cpu == 0.1)
        #expect(meter.history.samples.isEmpty)
    }

    @Test func aCounterThatWentBackSkipsOneSample() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 9_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 10_000))
        let reset = meter.take(reading(at: 4, busy: 20, total: 300, received: 50))
        #expect(reset?.isOnline == true)
        #expect(reset?.network == nil)
        #expect(meter.history.samples.count == 1)
    }

    @Test func theGraphKeepsTheLastThirtySamples() {
        var history = NetworkHistory()
        for index in 0..<35 { history.append(NetworkSpeed(down: Double(index), up: 0)) }
        #expect(history.samples.count == 30)
        #expect(history.samples.first?.down == 5)
        #expect(history.samples.last?.down == 34)
    }

    @Test func bothLinesShareOneScale() {
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 1_000_000, up: 250_000))
        history.append(NetworkSpeed(down: 4_000_000, up: 2_000_000))
        #expect(history.scale == 4_000_000)
        #expect(history.downFractions == [0.25, 1])
        #expect(history.upFractions == [0.0625, 0.5])
    }

    @Test func aQuietNetworkDoesNotFillTheGraph() {
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 2_000, up: 500))
        // Below 100 KB/s the scale stays there, so idle chatter stays near the floor.
        #expect(history.scale == 100_000)
        #expect(history.downFractions == [0.02])
        #expect(NetworkHistory().scale == 100_000)
    }
}
```

Add to `IslandStateTests.swift`, at the end of the struct (before its closing brace):

```swift
    @Test func theSystemSnapshotIsKept() {
        let state = IslandState()
        #expect(state.system == nil)
        #expect(state.networkHistory.samples.isEmpty)
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 2_000, up: 200))
        let snapshot = SystemSnapshot(
            cpu: 0.3, gpu: 0.2, memory: MemoryUse(used: 20, total: 48),
            temperatures: Temperatures(cpu: 44, gpu: 37), network: NetworkSpeed(down: 2_000, up: 200),
            isOnline: true)
        state.setSystem(snapshot, history: history)
        #expect(state.system == snapshot)
        #expect(state.networkHistory == history)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -15`
Expected: the build fails with `cannot find 'SystemMeter' in scope`.

- [ ] **Step 3: Write the code**

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/SystemMeter.swift`:

```swift
import Foundation

/// The chip's temperatures in °C; nil where none could be read.
public struct Temperatures: Equatable, Sendable {
    public var cpu: Double?
    public var gpu: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
    }
}

/// What one look at the system gave: counters and momentary values, nothing derived yet.
public struct SystemReading: Equatable, Sendable {
    public var date: Date
    public var cpu: CPUTicks?
    public var memory: MemoryUse?
    /// 0...1.
    public var gpu: Double?
    /// Nil when the temperatures were not read this time; they are read less often.
    public var temperatures: Temperatures?
    /// The primary interface's counters; nil while there is no network.
    public var counters: NetworkCounters?

    public init(
        date: Date, cpu: CPUTicks?, memory: MemoryUse?, gpu: Double?, temperatures: Temperatures?,
        counters: NetworkCounters?
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.temperatures = temperatures
        self.counters = counters
    }
}

/// What the System tab shows. A nil value could not be read and is drawn as a dash.
public struct SystemSnapshot: Equatable, Sendable {
    /// 0...1.
    public var cpu: Double?
    public var gpu: Double?
    public var memory: MemoryUse?
    public var temperatures: Temperatures
    /// Nil while offline, and for the one sample after the interface changed.
    public var network: NetworkSpeed?
    public var isOnline: Bool

    public init(
        cpu: Double?, gpu: Double?, memory: MemoryUse?, temperatures: Temperatures,
        network: NetworkSpeed?, isOnline: Bool
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.temperatures = temperatures
        self.network = network
        self.isOnline = isOnline
    }
}

/// The network speeds of the last minute, oldest first, for the graph.
public struct NetworkHistory: Equatable, Sendable {
    /// One sample every two seconds: a minute.
    public static let capacity = 30
    /// The graph's full height is never less than this, in bytes per second, so that the
    /// idle chatter of a quiet network stays near the floor.
    public static let minimumScale = 100_000.0

    public private(set) var samples: [NetworkSpeed] = []

    public init() {}

    public mutating func append(_ speed: NetworkSpeed) {
        samples.append(speed)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// The speed at the graph's full height: the fastest sample of either direction.
    public var scale: Double {
        samples.reduce(Self.minimumScale) { max($0, $1.down, $1.up) }
    }

    /// 0...1 per sample, on the shared scale.
    public var downFractions: [Double] {
        let scale = scale
        return samples.map { $0.down / scale }
    }

    public var upFractions: [Double] {
        let scale = scale
        return samples.map { $0.up / scale }
    }
}

/// Turns readings into what is shown. Use and speed come from two readings, so the first
/// one, and the first after a gap, only primes the meter.
public struct SystemMeter: Sendable {
    private var last: SystemReading?
    private var temperatures = Temperatures()
    public private(set) var history = NetworkHistory()

    public init() {}

    /// Nil when this reading could only prime the meter.
    public mutating func take(_ reading: SystemReading) -> SystemSnapshot? {
        let earlier = last
        last = reading
        if let read = reading.temperatures { temperatures = read }
        guard let earlier else { return nil }
        let elapsed = reading.date.timeIntervalSince(earlier.date)
        guard elapsed > 0, elapsed <= NetworkRate.maximumGap else {
            // The tab was hidden or the Mac slept: what the graph held is not the last minute.
            history.reset()
            return nil
        }
        let speed = NetworkRate.speed(previous: earlier.counters, current: reading.counters, elapsed: elapsed)
        if let speed {
            history.append(speed)
        } else if reading.counters == nil {
            history.reset()
        }
        return SystemSnapshot(
            cpu: CPUUsage.fraction(previous: earlier.cpu, current: reading.cpu), gpu: reading.gpu,
            memory: reading.memory, temperatures: temperatures, network: speed,
            isOnline: reading.counters != nil)
    }
}
```

In `IslandState.swift`, after the `volumes` property (it ends with `public private(set) var volumes: [VolumeTarget: Double] = [:]`), add:

```swift

    /// This Mac's last measures, for the System tab; nil until the first has been taken.
    public private(set) var system: SystemSnapshot?
    /// The network speeds of the last minute the System tab was looked at.
    public private(set) var networkHistory = NetworkHistory()
```

After the `setVolume(_:for:)` method, add:

```swift

    /// A new measure of this Mac, with the graph it belongs to.
    public func setSystem(_ snapshot: SystemSnapshot, history: NetworkHistory) {
        // Assign only on change: every assignment redraws the island.
        if system != snapshot { system = snapshot }
        if networkHistory != history { networkHistory = history }
    }
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: all tests pass (785 + 11 = 796).

- [ ] **Step 5: Build the app and commit**

Run the `xcodebuild` line from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): turn system readings into a snapshot" -m "Use and speed need two readings, and a reading after sleep must not be compared with one from before it. The meter holds that rule and the graph's last minute, so the app only reads and hands over."
git push origin main
```

---

### Task 3: The tab and its glyph

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandTab.swift:4-12`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandTabTests.swift`, `IslandStateTests.swift`
- Modify: `Symbiodock/Island/TabStrip.swift:64-72`, `Symbiodock/Island/TabGlyph.swift`, `Symbiodock/Island/ExpandedIsland.swift:30-46`, `Symbiodock/Island/IslandView.swift:93-105`, `Symbiodock/App/DebugRender.swift`
- Create: `Symbiodock/Island/System/SystemContent.swift`

**Interfaces:**
- Consumes: `SystemSnapshot`, `NetworkHistory`, `IslandState.system`, `.networkHistory` (Task 2).
- Produces: `IslandTab.system` (raw value `"system"`); `TabOrder.default == [.agents, .media, .system, .files]`; `TabGlyphOutline.system`; `SystemContent(snapshot: SystemSnapshot?, history: NetworkHistory, topInset: CGFloat)` (an empty page in this task; Task 4 fills it).

- [ ] **Step 1: Update the tests that spell out the order**

Every full order in the two test files gains `.system` before `.files`:

```bash
sed -i '' 's/, \.files\]/, .system, .files]/g' \
  Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandTabTests.swift \
  Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift
git diff --stat
```

Read the diff: only arrays that list a whole order may have changed (expected about 20 lines in `IslandTabTests.swift` and 3 in `IslandStateTests.swift`).

Add to `IslandTabTests.swift`, at the end of the struct:

```swift
    @Test func systemSitsBetweenMediaAndFiles() {
        #expect(TabOrder.default == [.agents, .media, .system, .files])
        // An order saved before the tab existed gains it in its place.
        #expect(TabOrder.repaired(["agents", "media", "files"]) == [.agents, .media, .system, .files])
        #expect(TabOrder.repaired(["media", "agents", "files"]) == [.media, .agents, .system, .files])
    }

    @Test func systemCannotBeMovedToTheFront() {
        #expect(TabOrder.reorderable == [.agents, .media])
        #expect(TabOrder.moving(.system, toFrontOf: TabOrder.default) == TabOrder.default)
    }

    @Test func nothingOpensOnTheSystemTabByItself() {
        func open(media: Bool, agents: Bool, files: Bool) -> IslandTab {
            TabSelection.tabToOpen(
                order: TabOrder.default, attention: .none, mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: media, agentsHasContent: agents, filesHasContent: files)
        }
        #expect(open(media: false, agents: false, files: false) == .agents)
        #expect(open(media: false, agents: false, files: true) == .files)
        #expect(open(media: true, agents: false, files: true) == .media)
    }
```

Add to `IslandStateTests.swift`, at the end of the struct:

```swift
    @Test func theSystemTabIsLeftWhenTheIslandCloses() {
        let state = IslandState()
        state.setHovering(true)
        state.selectTab(.system)
        #expect(state.selectedTab == .system)
        state.setHovering(false)
        state.setHovering(true)
        // It never opens by itself: the usual rule chooses again.
        #expect(state.selectedTab == .agents)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -15`
Expected: the build fails with `type 'IslandTab' has no member 'system'`.

- [ ] **Step 3: Add the tab to the core**

In `IslandTab.swift`, replace the enum and the default order:

```swift
/// The pages of the expanded island.
public enum IslandTab: String, CaseIterable, Sendable {
    case agents
    case media
    case system
    case files
}
```

```swift
    public static let `default`: [IslandTab] = [.agents, .media, .system, .files]

    /// The tabs the user may put first. System and Files keep their places at the end.
    public static let reorderable: [IslandTab] = [.agents, .media]
```

`repaired` appends a missing tab in default order; after the review it also moves every tab that cannot be put first (System, then Files) to the end, so a stored list that names System first cannot make the island open on it. `tabToOpen` and `face` pass over tabs they do not name.

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: all tests pass (796 + 4 = 800).

- [ ] **Step 4: Wire the tab into the app**

`Symbiodock/Island/TabStrip.swift`, in `IslandTab.title`, after the media case:

```swift
        case .system: "System"
```

`Symbiodock/Island/TabGlyph.swift`, in `outline(for:)`, after the media case:

```swift
        case .system: system
```

and after the `media` drawing (before the `files` drawing):

```swift
    /// A chip: the processor the tab measures. A small rounded square with two legs on each
    /// side; the legs end on the square's own line, so they join it.
    static let system: Path = {
        var legs = Path()
        for at in [5.75, 8.25] as [CGFloat] {
            legs.move(to: CGPoint(x: at, y: 2.25))
            legs.addLine(to: CGPoint(x: at, y: 4.25))
            legs.move(to: CGPoint(x: at, y: 9.75))
            legs.addLine(to: CGPoint(x: at, y: 11.75))
            legs.move(to: CGPoint(x: 2.25, y: at))
            legs.addLine(to: CGPoint(x: 4.25, y: at))
            legs.move(to: CGPoint(x: 9.75, y: at))
            legs.addLine(to: CGPoint(x: 11.75, y: at))
        }
        return outline(of: [
            Part(card(x0: 4.25, y0: 4.25, x1: 9.75, y1: 9.75, folded: 0)),
            Part(legs),
        ])
    }()
```

Also change the type's doc comment from "The three drawings" to "The four drawings".

Create `Symbiodock/Island/System/SystemContent.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The System tab: how busy and how warm this Mac is, and how fast its network.
struct SystemContent: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory
    /// The header band's height; the page starts below it.
    let topInset: CGFloat

    var body: some View {
        Color.clear
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Symbiodock/Island/ExpandedIsland.swift`, in the content switch, after the agents case:

```swift
                case .system:
                    SystemContent(
                        snapshot: state.system, history: state.networkHistory,
                        topInset: metrics.height)
```

`Symbiodock/Island/IslandView.swift`, in `bubbleContent`:

```swift
        case .system, .files, nil:
            // System and Files never have a face, so they never move out to the bubble.
            nil
```

`Symbiodock/App/DebugRender.swift`:

- The glyph gallery is wider now. Change its render size:

```swift
        write(TabGlyphGallery(), size: CGSize(width: 1300, height: 290), named: "tab-glyphs", to: directory)
```

- In `TabGlyphGallery.body`, the strip is four buttons now:

```swift
                // Three times larger, to weigh the glyphs against each other. The strip is
                // four 28-point buttons 2 apart: 118 points wide.
                strip(.agents)
                    .scaleEffect(3, anchor: .leading)
                    .frame(width: 118 * 3, height: 22 * 3, alignment: .leading)
```

- The doc comment of `ExpandedPreview` says "600 × 150"; the island is 600 × 170. Correct the comment.

- [ ] **Step 5: Build and look**

Run the `xcodebuild` line from Global Constraints. Expected: `** BUILD SUCCEEDED **`. If the compiler names another `switch` over `IslandTab` that is not exhaustive, give `.system` the same answer as `.files` there and note it in this plan.

Run: `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
Read `build/render/tab-glyphs.png`. Expected: four glyphs on their grids; the fourth column is not cut off; the chip is a square with eight legs, its strokes on whole pixels in the 2x view; the real strips show four tabs in the order terminal, bars, chip, cards.

- [ ] **Step 6: Commit**

```bash
git add Packages/SymbiodockCore Symbiodock/Island Symbiodock/App/DebugRender.swift
git commit -m "feat(island): add the System tab and its chip glyph" -m "The owner asked for a tab that shows how this Mac is doing. It sits before Files, cannot be put first and never opens by itself: it always has something to show, so it would otherwise open ahead of Files on every idle hover."
git push origin main
```

---

### Task 4: The page

**Files:**
- Create: `Symbiodock/Island/System/SystemPalette.swift`, `Symbiodock/Island/System/MeterBar.swift`, `Symbiodock/System/DemoSystem.swift`
- Modify: `Symbiodock/Island/System/SystemContent.swift` (replace the file), `Symbiodock/App/AppDelegate.swift:68`, `Symbiodock/App/DebugRender.swift`

**Interfaces:**
- Consumes: `SystemSnapshot`, `NetworkHistory`, `SystemLabels`, `TemperatureTier`, `IslandState.setSystem(_:history:)`.
- Produces: `SystemPalette.cpu`, `.gpu`, `.ram` (`[NSColor]`, left to right), `.down`, `.downFade`, `.up` (`Color`), `.color(for: TemperatureTier) -> Color`; `MeterBar(fraction: Double?, colors: [NSColor])`; `DemoSystem.requested: String?`, `DemoSystem.apply(_ set: String, to: IslandState)` (`"1"` calm, `"hot"` busy).

- [ ] **Step 1: The colours**

`Symbiodock/Island/System/SystemPalette.swift`:

```swift
import AppKit
import SwiftUI
import SymbiodockCore

/// The colours of the System tab: each measure has its own, the owner's choice from the
/// mockup. None says "good" or "bad"; only a temperature's number changes colour with heat.
@MainActor
enum SystemPalette {
    /// Left to right along the bar.
    static let cpu = [rgb(0x2F7BFF), rgb(0x5EE7FF)]
    static let gpu = [rgb(0xA45CFF), rgb(0xFF7EDB)]
    static let ram = [rgb(0x34D17A), rgb(0xC6F56B)]

    static let down = Color(nsColor: rgb(0x7CF5C8))
    /// What the area under the download line fades to.
    static let downFade = Color(nsColor: rgb(0x2BD4A4))
    static let up = Color(nsColor: rgb(0xFFB86B))

    static func color(for tier: TemperatureTier) -> Color {
        switch tier {
        case .normal: .white.opacity(0.55)
        case .warm: Color(nsColor: rgb(0xFFD60A))
        case .hot: Color(nsColor: rgb(0xFF6B5E))
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
```

- [ ] **Step 2: The bar**

`Symbiodock/Island/System/MeterBar.swift`:

```swift
import AppKit
import SwiftUI

/// A bar that fills with a measure. Its layers are Core Animation's: when the measure
/// changes, the render server moves the fill and the app does no work per frame
/// (see `LayerAnimation.swift`).
struct MeterBar: NSViewRepresentable {
    /// Seconds the fill takes to reach a new value.
    static let transition: CFTimeInterval = 0.6

    /// 0...1; nil while the measure is unknown: the track alone.
    let fraction: Double?
    /// Left to right.
    let colors: [NSColor]

    func makeNSView(context: Context) -> BarView { BarView() }

    func updateNSView(_ view: BarView, context: Context) {
        view.configure(fraction: fraction, colors: colors)
    }

    final class BarView: NSView {
        private let track = CALayer()
        /// The fill's soft light; a layer of its own, because the fill clips to its bounds.
        private let glow = CALayer()
        private let fill = CAGradientLayer()
        private var fraction: Double?
        private var colors: [NSColor] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            track.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            glow.shadowOffset = .zero
            glow.shadowRadius = 3
            glow.shadowOpacity = 0.55
            fill.startPoint = CGPoint(x: 0, y: 0.5)
            fill.endPoint = CGPoint(x: 1, y: 0.5)
            fill.masksToBounds = true
            for part in [track, glow, fill] {
                part.anchorPoint = CGPoint(x: 0, y: 0.5)
                layer?.addSublayer(part)
            }
            glow.isHidden = true
            fill.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(fraction: Double?, colors: [NSColor]) {
            if self.colors != colors {
                self.colors = colors
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                fill.colors = colors.map(\.cgColor)
                glow.backgroundColor = colors.last?.cgColor
                glow.shadowColor = colors.last?.cgColor
                CATransaction.commit()
            }
            let clamped = fraction.map { min(1, max(0, $0)) }
            guard clamped != self.fraction else { return }
            // A bar that was empty appears at its value; only a change of value moves.
            let moves = self.fraction != nil && clamped != nil && window != nil
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.fraction = clamped
            place(animated: moves)
        }

        override func layout() {
            super.layout()
            place(animated: false)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            for part in [track, glow, fill] { part.contentsScale = scale }
        }

        private func place(animated: Bool) {
            CATransaction.begin()
            if animated {
                CATransaction.setAnimationDuration(MeterBar.transition)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1))
            } else {
                CATransaction.setDisableActions(true)
            }
            let height = bounds.height
            let origin = CGPoint(x: 0, y: bounds.midY)
            track.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            track.position = origin
            track.cornerRadius = height / 2
            // Never shorter than it is high: a measure near zero is a dot, not nothing.
            let width = max(bounds.width * (fraction ?? 0), height)
            for part in [glow, fill] {
                part.isHidden = fraction == nil
                part.bounds = CGRect(x: 0, y: 0, width: width, height: height)
                part.position = origin
                part.cornerRadius = height / 2
            }
            CATransaction.commit()
        }
    }
}
```

- [ ] **Step 3: The page**

Replace `Symbiodock/Island/System/SystemContent.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// The System tab: how busy and how warm this Mac is, and how fast its network. Three
/// columns: the measures with their bars, the network panel, the devices panel.
///
/// The texts and the graph change only when a new sample arrives (every two seconds); the
/// bars move in Core Animation. Nothing here redraws by itself.
struct SystemContent: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory
    /// The header band's height; the page starts below it.
    let topInset: CGFloat

    private static let topGap: CGFloat = 2
    private static let sideMargin: CGFloat = 16
    private static let bottomMargin: CGFloat = 14
    private static let columnGap: CGFloat = 10
    private static let networkWidth: CGFloat = 128
    private static let devicesWidth: CGFloat = 164

    var body: some View {
        HStack(spacing: Self.columnGap) {
            meters
            NetworkPanel(snapshot: snapshot, history: history)
                .frame(width: Self.networkWidth)
            DevicesPanel()
                .frame(width: Self.devicesWidth)
        }
        .padding(.top, topInset + Self.topGap)
        .padding(.horizontal, Self.sideMargin)
        .padding(.bottom, Self.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meters: some View {
        VStack(spacing: 0) {
            MeterRow(title: "CPU", fraction: snapshot?.cpu, colors: SystemPalette.cpu) {
                temperature(snapshot?.temperatures.cpu)
                value(SystemLabels.percent(snapshot?.cpu))
            }
            .accessibilityValue(spoken(snapshot?.cpu, snapshot?.temperatures.cpu))
            Spacer(minLength: 0)
            MeterRow(title: "GPU", fraction: snapshot?.gpu, colors: SystemPalette.gpu) {
                temperature(snapshot?.temperatures.gpu)
                value(SystemLabels.percent(snapshot?.gpu))
            }
            .accessibilityValue(spoken(snapshot?.gpu, snapshot?.temperatures.gpu))
            Spacer(minLength: 0)
            MeterRow(title: "RAM", fraction: snapshot?.memory?.fraction, colors: SystemPalette.ram) {
                memory(snapshot?.memory)
            }
            .accessibilityValue(spokenMemory(snapshot?.memory))
        }
        .padding(.vertical, 7)
        .padding(.leading, 2)
        .padding(.trailing, 4)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 36, alignment: .trailing)
    }

    private func temperature(_ celsius: Double?) -> some View {
        Text(SystemLabels.degrees(celsius))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(SystemPalette.color(for: SystemLabels.tier(celsius)))
    }

    @ViewBuilder
    private func memory(_ use: MemoryUse?) -> some View {
        if let use {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(SystemLabels.gigabytes(use.used))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("/ \(SystemLabels.wholeGigabytes(use.total)) GB")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            value(SystemLabels.missing)
        }
    }

    private func spoken(_ fraction: Double?, _ celsius: Double?) -> String {
        guard let fraction else { return "Unknown" }
        let percent = "\(Int((fraction * 100).rounded())) percent"
        guard let celsius else { return percent }
        return "\(percent), \(Int(celsius.rounded())) degrees"
    }

    private func spokenMemory(_ use: MemoryUse?) -> String {
        guard let use else { return "Unknown" }
        return "\(SystemLabels.gigabytes(use.used)) of \(SystemLabels.wholeGigabytes(use.total)) gigabytes"
    }
}

/// One measure: its name, what it reads, and a bar under them.
private struct MeterRow<Trailing: View>: View {
    let title: String
    let fraction: Double?
    let colors: [NSColor]
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                trailing()
            }
            MeterBar(fraction: fraction, colors: colors)
                .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// The small caption at the top of a panel.
private struct PanelCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.35))
    }
}

private extension View {
    /// The faint rounded box a panel sits in.
    func systemPanel() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Download and upload speed, and the last minute of both.
private struct NetworkPanel: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelCaption("NETWORK")
            if snapshot?.isOnline == false {
                Text("Offline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
            } else {
                rate(snapshot?.network?.down, pointsDown: true, color: SystemPalette.down)
                    .padding(.top, 6)
                    .accessibilityLabel("Download")
                rate(snapshot?.network?.up, pointsDown: false, color: SystemPalette.up)
                    .padding(.top, 3)
                    .accessibilityLabel("Upload")
            }
            Spacer(minLength: 4)
            NetworkGraph(history: history)
                .frame(height: 34)
        }
        .systemPanel()
    }

    private func rate(_ bytesPerSecond: Double?, pointsDown: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            RateArrow(pointsDown: pointsDown)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 9, height: 9)
            Text(bytesPerSecond.map(SystemLabels.rate) ?? SystemLabels.missing)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An arrow on a 9-point square: a shaft and a head.
private struct RateArrow: Shape {
    let pointsDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip: CGFloat = pointsDown ? 7.7 : 1.3
        let tail: CGFloat = pointsDown ? 1.5 : 7.5
        let barbs: CGFloat = pointsDown ? 5 : 4
        path.move(to: CGPoint(x: 4.5, y: tail))
        path.addLine(to: CGPoint(x: 4.5, y: tip))
        path.move(to: CGPoint(x: 1.8, y: barbs))
        path.addLine(to: CGPoint(x: 4.5, y: tip))
        path.addLine(to: CGPoint(x: 7.2, y: barbs))
        return path.applying(CGAffineTransform(scaleX: rect.width / 9, y: rect.height / 9))
    }
}

/// The last minute: download as a filled line, upload as a thin one, on one scale.
private struct NetworkGraph: View {
    let history: NetworkHistory

    var body: some View {
        ZStack {
            GraphLine(values: history.downFractions, closes: true)
                .fill(
                    LinearGradient(
                        colors: [SystemPalette.down.opacity(0.5), SystemPalette.downFade.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
            GraphLine(values: history.upFractions)
                .stroke(
                    SystemPalette.up.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            GraphLine(values: history.downFractions)
                .stroke(
                    SystemPalette.down, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A line through samples, the newest at the right edge. A sample always takes the same
/// width, so a graph that is not full yet grows in from the right.
private struct GraphLine: Shape {
    /// 0...1 each.
    let values: [Double]
    /// Whether the line is closed along the bottom, to be filled.
    var closes = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let inset: CGFloat = 2
        let step = rect.width / CGFloat(NetworkHistory.capacity - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.maxX - step * CGFloat(values.count - 1 - index),
                y: rect.maxY - inset - (rect.height - 2 * inset) * CGFloat(min(1, max(0, value))))
        }
        path.addLines(points)
        if closes, let first = points.first {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// The devices on the network. Finding them needs the Local Network permission; until that
/// part is built the panel holds its place with a dash.
private struct DevicesPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelCaption("DEVICES")
            Spacer(minLength: 0)
            Text(SystemLabels.missing)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .systemPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Devices")
        .accessibilityValue("Unknown")
    }
}
```

- [ ] **Step 4: The demo and the renders**

`Symbiodock/System/DemoSystem.swift`:

```swift
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
```

`Symbiodock/App/AppDelegate.swift`: between the block that starts the agents (it ends with `#endif` after `startAgents()`) and the `DemoMedia` block, add:

```swift

        #if DEBUG
        if let demo = DemoSystem.requested { DemoSystem.apply(demo, to: state) }
        #endif
```

`Symbiodock/App/DebugRender.swift`, before the `CollapsedGallery` line:

```swift
        for (name, set) in [("expanded-system", "1"), ("expanded-system-hot", "hot")] {
            let system = IslandState()
            DemoSystem.apply(set, to: system)
            system.setHovering(true)
            system.selectTab(.system)
            write(
                ExpandedPreview(state: system), size: CGSize(width: 640, height: 210),
                named: name, to: directory)
        }
        // Before the first measure: dashes, tracks without fills, an empty graph.
        let unmeasured = IslandState()
        unmeasured.setHovering(true)
        unmeasured.selectTab(.system)
        write(
            ExpandedPreview(state: unmeasured), size: CGSize(width: 640, height: 210),
            named: "expanded-system-empty", to: directory)
```

- [ ] **Step 5: Build and look**

Run the `xcodebuild` line. Expected: `** BUILD SUCCEEDED **`.

Run the render line, then read `build/render/expanded-system.png`, `expanded-system-hot.png` and `expanded-system-empty.png`, with the mockup's screenshot beside them if it helps (`.superpowers/brainstorm/7804-1795251702/content/system-tab-layouts.html`, layout A). Check:

- Three rows left: `CPU 45° 31%`, `GPU 46° 24%`, `RAM 18.5 / 48 GB`, each with a bar in its own colours (blue, purple to pink, green), filled to its value.
- `NETWORK` panel: two rates with a teal arrow down and an orange arrow up, the graph along the bottom.
- `DEVICES` panel: the caption and a dash.
- Nothing touches the island's edge or the header; nothing is clipped at the rounded bottom corners.
- Hot: `96°` red, `83°` yellow, bars nearly full, `41.4 MB/s`.
- Empty: dashes, tracks without fills, no graph.

If the bars are missing from the renders while everything else is there, the offscreen capture did not include the layers (the level bars of the Media renders are layers too, so this is not expected). Then give the bar a still twin for renders only: an environment value `\.stillMeters` (default `false`) that `DebugRender` sets on `ExpandedPreview` with `.environment(\.stillMeters, true)`; `MeterRow` reads it and, when it is true, draws the bar with SwiftUI instead of `MeterBar`: in a `GeometryReader`, a `Capsule().fill(.white.opacity(0.14))` with a `Capsule` on top filled by `LinearGradient(colors: colors.map(Color.init(nsColor:)), startPoint: .leading, endPoint: .trailing)` and framed to `max(width * fraction, 6)`, aligned leading. Record that in this plan.

- [ ] **Step 6: See it in the running app**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_SYSTEM=hot --env SYMBIODOCK_DEMO_AGENTS=quiet build/Build/Products/Debug/Symbiodock.app
sleep 3 && swift scripts/list-windows.swift && top -l 3 -s 2 -pid $(pgrep -x Symbiodock) -stats pid,cpu | tail -1
pkill -x Symbiodock
```

Expected: the app runs, its panel is listed, CPU 0.0 with the island closed.

- [ ] **Step 7: Commit**

```bash
git add Symbiodock docs/superpowers/plans/2026-11-21-system-tab-a.md
git commit -m "feat(island): draw the System tab's page" -m "Layout A, the chip glyph and one colour per measure are what the owner picked from the live mockup. The bars are layers, so a new value every two seconds does not keep the panel's update cycle running."
git push origin main
```

---

### Task 5: Reading the system

**Files:**
- Create: `Symbiodock/System/HostSampler.swift`, `GPUProbe.swift`, `SMCReader.swift`, `ThermalFallback.swift`, `NetworkCounterReader.swift`, `SystemReader.swift`, `SystemCoordinator.swift`
- Modify: `Symbiodock/System/DemoSystem.swift` (add `SystemHook`), `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `CPUTicks`, `MemoryPages`, `MemoryUsage`, `MemoryUse`, `NetworkCounters`, `TemperatureKeys`, `Temperatures`, `SystemReading`, `SystemMeter`, `SystemSnapshot`, `NetworkHistory`, `SystemLabels`, `IslandState.setSystem(_:history:)`, `.phase`, `.selectedTab`.
- Produces: `HostSampler.cpuTicks() -> CPUTicks?`, `HostSampler.memory() -> MemoryUse?`, `GPUProbe.utilization() -> Double?`, `SMCReader()` (failable) with `temperatures() -> Temperatures`, `ThermalFallback.dieTemperature() -> Double?`, `NetworkCounterReader.counters(store:) -> NetworkCounters?`, `actor SystemReader` with `read(withTemperatures: Bool) -> SystemReading`, `SystemCoordinator(isWatching:onUpdate:)` with `start()` and `stop()`, `SystemHook.runIfRequested() -> Bool`.

All of these reads were run as a script on this Mac on 2026-11-21 (M4 Pro, macOS 27.0.1, no `sudo`, no prompt): CPU 8 %, memory 21.0 of 48 GB, GPU 26 %, 3462 SMC keys of which 110 are valid chip temperatures (median CPU 44.0 °C, GPU 36.6 °C), `en0` counters and their rate.

- [ ] **Step 1: Processor and memory**

`Symbiodock/System/HostSampler.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore

/// The processor's and the memory's counters, from the kernel's host statistics. No
/// permission is needed.
enum HostSampler {
    /// Asked for once: every call of `mach_host_self` adds a reference to the port.
    private static let host = mach_host_self()

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let (user, system, idle, nice) = info.cpu_ticks
        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        return CPUTicks(busy: busy, total: busy + UInt64(idle))
    }

    static func memory() -> MemoryUse? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        let pages = MemoryPages(
            internalPages: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
            wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count))
        return MemoryUse(
            used: MemoryUsage.used(pages, pageSize: UInt64(pageSize)),
            total: ProcessInfo.processInfo.physicalMemory)
    }
}
```

- [ ] **Step 2: Graphics**

`Symbiodock/System/GPUProbe.swift`:

```swift
import Foundation
import IOKit

/// How busy the graphics processor is, from the statistics its driver publishes in the
/// I/O registry (what Activity Monitor's GPU history shows). No permission is needed.
enum GPUProbe {
    /// 0...1; the busiest, where there is more than one. Nil when no driver reports it.
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let property = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            guard let statistics = property as? [String: Any],
                  let percent = statistics["Device Utilization %"] as? NSNumber
            else { continue }
            busiest = max(busiest ?? 0, min(1, max(0, percent.doubleValue / 100)))
        }
        return busiest
    }
}
```

- [ ] **Step 3: Temperatures**

`Symbiodock/System/SMCReader.swift`:

```swift
import Foundation
import IOKit
import SymbiodockCore

/// Reads the chip's temperatures from the System Management Controller through its user
/// client. No permission and no root are needed for reading.
///
/// The controller is asked with an 80-byte structure. It is built as bytes with the fields
/// at their offsets (key 0, data size 28, data type 32, result 40, command 42, index 44,
/// data 48), because a Swift struct does not promise the C layout.
final class SMCReader {
    private struct Key {
        var code: UInt32
        var size: UInt32
    }

    private static let structSize = 80
    /// The selector of the controller's one call; the command is a byte in the structure.
    private static let selector: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readIndex: UInt8 = 8
    private static let readInfo: UInt8 = 9
    private static let floatType = code("flt ")

    private let connection: io_connect_t
    /// The keys read each time; nil until they have been chosen.
    private var cpuKeys: [Key]?
    private var gpuKeys: [Key] = []

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// The median of the processor's and of the graphics keys; nil where the chip has none
    /// under the names this reader knows.
    func temperatures() -> Temperatures {
        if cpuKeys == nil { chooseKeys() }
        return Temperatures(
            cpu: TemperatureKeys.typical((cpuKeys ?? []).compactMap(value)),
            gpu: TemperatureKeys.typical(gpuKeys.compactMap(value)))
    }

    /// Walks every key once and keeps a spread subset of the chip's temperature keys that
    /// read a valid value now. About 50 ms on an M4 Pro, once.
    private func chooseKeys() {
        var cpu: [Key] = []
        var gpu: [Key] = []
        for index in 0..<keyCount() {
            guard let code = key(at: index),
                  let sensor = TemperatureKeys.sensor(forKey: Self.name(code)),
                  let info = info(code), info.type == Self.floatType, info.size == 4
            else { continue }
            let candidate = Key(code: code, size: info.size)
            guard let read = value(candidate), TemperatureKeys.validRange.contains(read) else { continue }
            if sensor == .cpu { cpu.append(candidate) } else { gpu.append(candidate) }
        }
        cpuKeys = TemperatureKeys.spread(cpu, limit: TemperatureKeys.cpuLimit)
        gpuKeys = TemperatureKeys.spread(gpu, limit: TemperatureKeys.gpuLimit)
    }

    private func value(_ key: Key) -> Double? {
        guard let output = call(request(key: key.code, command: Self.readBytes, dataSize: key.size))
        else { return nil }
        let float = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 48, as: Float.self) }
        return Double(float)
    }

    private func keyCount() -> Int {
        let count = Self.code("#KEY")
        guard let info = info(count),
              let output = call(request(key: count, command: Self.readBytes, dataSize: info.size))
        else { return 0 }
        // The count is big-endian.
        return Int(output[48]) << 24 | Int(output[49]) << 16 | Int(output[50]) << 8 | Int(output[51])
    }

    private func key(at index: Int) -> UInt32? {
        call(request(command: Self.readIndex, index: UInt32(index))).map { word($0, at: 0) }
    }

    private func info(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        call(request(key: key, command: Self.readInfo)).map { (word($0, at: 28), word($0, at: 32)) }
    }

    private func request(key: UInt32 = 0, command: UInt8, dataSize: UInt32 = 0, index: UInt32 = 0) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.structSize)
        func put(_ value: UInt32, at offset: Int) {
            for byte in 0..<4 { bytes[offset + byte] = UInt8((value >> (8 * UInt32(byte))) & 0xFF) }
        }
        put(key, at: 0)
        put(dataSize, at: 28)
        bytes[42] = command
        put(index, at: 44)
        return bytes
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let result = IOConnectCallStructMethod(
            connection, Self.selector, input, Self.structSize, &output, &outputSize)
        // Byte 40 is the controller's own result; 0 is success.
        guard result == KERN_SUCCESS, output[40] == 0 else { return nil }
        return output
    }

    private func word(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    /// "Tp0D" → its four characters as one number, the first the highest byte.
    private static func code(_ name: String) -> UInt32 {
        name.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func name(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? ""
    }
}
```

`Symbiodock/System/ThermalFallback.swift`:

```swift
import Foundation
import IOKit

/// The chip's die temperature from the HID sensor services, for a Mac whose controller has
/// no temperature keys under the names `SMCReader` knows. The calls are private (IOKit's
/// HID event system client), so they are looked up at run time; where one is missing there
/// is no temperature. No permission is needed.
enum ThermalFallback {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValue = @convention(c) (AnyObject, Int32) -> Double

    private struct Calls {
        let create: Create
        let setMatching: SetMatching
        let copyServices: CopyServices
        let copyProperty: CopyProperty
        let copyEvent: CopyEvent
        let floatValue: FloatValue
    }

    /// The temperature event type and its level field, as IOKit numbers them.
    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private static let calls: Calls? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        func symbol<Call>(_ name: String, as type: Call.Type) -> Call? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", as: Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", as: FloatValue.self)
        else { return nil }
        return Calls(
            create: create, setMatching: setMatching, copyServices: copyServices,
            copyProperty: copyProperty, copyEvent: copyEvent, floatValue: floatValue)
    }()

    /// The mean of the die sensors (`PMU tdie…`) that read a plausible value, in °C.
    static func dieTemperature() -> Double? {
        guard let calls, let client = calls.create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        // Apple vendor usage page, temperature sensor.
        _ = calls.setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = calls.copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return nil }
        var readings: [Double] = []
        for service in services {
            guard let name = calls.copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.hasPrefix("PMU tdie"),
                  let event = calls.copyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue()
            else { continue }
            let value = calls.floatValue(event, temperatureField)
            if (10...120).contains(value) { readings.append(value) }
        }
        return readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
    }
}
```

- [ ] **Step 4: The network counters**

`Symbiodock/System/NetworkCounterReader.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore
import SystemConfiguration

/// The byte counters of the interface the default route uses. No permission is needed.
enum NetworkCounterReader {
    /// Nil while there is no network, and when the counters cannot be read.
    static func counters(store: SCDynamicStore?) -> NetworkCounters? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let interface = global["PrimaryInterface"] as? String
        else { return nil }
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        // The 64-bit counters; `getifaddrs` gives 32-bit ones that wrap at 4 GB.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self) }
            guard header.ifm_msglen > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2, UInt32(header.ifm_index) == index,
               offset + MemoryLayout<if_msghdr2>.size <= length {
                let full = buffer.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                }
                return NetworkCounters(
                    interface: interface, received: full.ifm_data.ifi_ibytes, sent: full.ifm_data.ifi_obytes)
            }
            offset += Int(header.ifm_msglen)
        }
        return nil
    }
}
```

- [ ] **Step 5: One whole reading**

`Symbiodock/System/SystemReader.swift`:

```swift
import Foundation
import SymbiodockCore
import SystemConfiguration

/// Takes one reading of the system. An actor, so the reads run off the main thread and one
/// at a time; it keeps the controller's connection and the chosen keys between readings.
actor SystemReader {
    private var smc: SMCReader?
    private var hasTriedSMC = false
    private let store = SCDynamicStoreCreate(nil, "Symbiodock" as CFString, nil, nil)

    /// - Parameter withTemperatures: they change slowly and cost the most to read.
    func read(withTemperatures: Bool) -> SystemReading {
        SystemReading(
            date: Date(), cpu: HostSampler.cpuTicks(), memory: HostSampler.memory(),
            gpu: GPUProbe.utilization(), temperatures: withTemperatures ? temperatures() : nil,
            counters: NetworkCounterReader.counters(store: store))
    }

    private func temperatures() -> Temperatures {
        if !hasTriedSMC {
            hasTriedSMC = true
            smc = SMCReader()
        }
        var read = smc?.temperatures() ?? Temperatures()
        if read.cpu == nil || read.gpu == nil, let die = ThermalFallback.dieTemperature() {
            // One die temperature stands for both: these sensors do not tell them apart.
            read.cpu = read.cpu ?? die
            read.gpu = read.gpu ?? die
        }
        return read
    }
}
```

- [ ] **Step 6: The loop**

`Symbiodock/System/SystemCoordinator.swift`:

```swift
import Foundation
import Observation
import SymbiodockCore
import os

/// Measures this Mac while the System tab is on screen, and only then: every two seconds,
/// off the main thread, and hands each snapshot to the app.
@MainActor
final class SystemCoordinator {
    /// Numbers only.
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "system"'`
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "system")
    private static let interval: Duration = .seconds(2)
    /// Use and speed need two readings; the second follows the first quickly.
    private static let primingInterval: Duration = .milliseconds(500)
    /// The temperatures are read with every third reading: every six seconds.
    private static let temperatureEvery = 3

    private let isWatching: @MainActor () -> Bool
    private let onUpdate: @MainActor (SystemSnapshot, NetworkHistory) -> Void
    private let reader = SystemReader()
    private var meter = SystemMeter()
    private var task: Task<Void, Never>?
    /// Tells the running loop from one that has been replaced.
    private var run = 0
    private var isStopped = true
    private var hasLogged = false

    /// - Parameter isWatching: whether the open island shows the System tab. It must read
    ///   observable state: the coordinator observes what it reads.
    init(
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor (SystemSnapshot, NetworkHistory) -> Void
    ) {
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard isStopped else { return }
        isStopped = false
        observe()
        refresh()
    }

    func stop() {
        isStopped = true
        endLoop()
    }

    /// Calls `refresh` whenever what `isWatching` read has changed.
    private func observe() {
        withObservationTracking {
            _ = isWatching()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isStopped else { return }
                self.observe()
                self.refresh()
            }
        }
    }

    private func refresh() {
        if isWatching() { beginLoop() } else { endLoop() }
    }

    private func beginLoop() {
        guard task == nil else { return }
        run += 1
        let mine = run
        task = Task { [weak self] in
            await self?.loop()
            self?.loopEnded(mine)
        }
    }

    private func endLoop() {
        task?.cancel()
        task = nil
    }

    private func loopEnded(_ id: Int) {
        if id == run { task = nil }
    }

    private func loop() async {
        var count = 0
        while !Task.isCancelled, isWatching() {
            let reading = await reader.read(withTemperatures: count % Self.temperatureEvery == 0)
            guard !Task.isCancelled else { return }
            count += 1
            let snapshot = meter.take(reading)
            if let snapshot {
                onUpdate(snapshot, meter.history)
                logOnce(snapshot)
            }
            try? await Task.sleep(for: snapshot == nil ? Self.primingInterval : Self.interval)
        }
    }

    /// Says once which measures this Mac gives.
    private func logOnce(_ snapshot: SystemSnapshot) {
        guard !hasLogged else { return }
        hasLogged = true
        Self.log.notice(
            """
            measuring: cpu \(snapshot.cpu != nil, privacy: .public) \
            gpu \(snapshot.gpu != nil, privacy: .public) \
            cpuTemp \(snapshot.temperatures.cpu != nil, privacy: .public) \
            gpuTemp \(snapshot.temperatures.gpu != nil, privacy: .public) \
            online \(snapshot.isOnline, privacy: .public)
            """)
    }
}
```

- [ ] **Step 7: A way to see the numbers without a window**

Append to `Symbiodock/System/DemoSystem.swift`, inside the `#if DEBUG` block, after `DemoSystem`:

```swift

/// `SYMBIODOCK_PRINT_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
/// prints four measures a second apart and quits, without building the island.
@MainActor
enum SystemHook {
    /// True when the hook took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["SYMBIODOCK_PRINT_SYSTEM"] != nil else { return false }
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
}
```

- [ ] **Step 8: Wire it**

`Symbiodock/App/AppDelegate.swift`:

- A property after `private var agents: AgentSessionCoordinator?`:

```swift
    private var system: SystemCoordinator?
```

- The debug hooks at the top of `applicationDidFinishLaunching`:

```swift
        if ConvertHook.runIfRequested() || FlowHook.runIfRequested() || SystemHook.runIfRequested() { return }
```

- Replace the block Task 4 added (`if let demo = DemoSystem.requested { … }` inside `#if DEBUG`) with:

```swift
        #if DEBUG
        if let demo = DemoSystem.requested {
            DemoSystem.apply(demo, to: state)
        } else {
            startSystem()
        }
        #else
        startSystem()
        #endif
```

- In `applicationWillTerminate`, after `agents?.stop()`:

```swift
        system?.stop()
```

- A method after `startAgents()`:

```swift
    /// Starts measuring this Mac whenever the open island shows the System tab.
    private func startSystem() {
        let system = SystemCoordinator(
            isWatching: { [weak self] in
                self.map { $0.state.phase == .expanded && $0.state.selectedTab == .system } ?? false
            },
            onUpdate: { [weak self] snapshot, history in
                self?.state.setSystem(snapshot, history: history)
            })
        system.start()
        self.system = system
    }
```

- [ ] **Step 9: Build and read the numbers**

Run the `xcodebuild` line. Expected: `** BUILD SUCCEEDED **`.

```bash
SYMBIODOCK_PRINT_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: four lines like `cpu 8% 44° | gpu 26% 37° | ram 21.0 / 48 GB | down 61 KB/s up 7 KB/s | online true | read 9000 µs`, and no permission window. Compare:

- GPU with `ioreg -r -d 1 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*'`.
- RAM with `vm_stat`: (`Anonymous pages` − `Pages purgeable` + `Pages wired down` + `Pages occupied by compressor`) × the page size ÷ 1073741824, within 0.3 GB.
- CPU with `top -l 2 -n 0 | grep "CPU usage" | tail -1` (100 − idle), within a few points.
- The first line's `read` time is the one-time key choice (about 50 ms); the later ones must be below 15 000 µs. If they are not, lower `TemperatureKeys.cpuLimit` and `gpuLimit` and say so in this plan.

Put load on the processor and read again; the CPU numbers must rise:

```bash
for i in 1 2 3 4 5 6 7 8; do (yes > /dev/null &); done; sleep 6
SYMBIODOCK_PRINT_SYSTEM=1 build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock; pkill -x yes
```

Expected: CPU above 50 % and a higher CPU temperature than before.

- [ ] **Step 10: The cost, closed and open**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=quiet build/Build/Products/Debug/Symbiodock.app
sleep 4 && top -l 6 -s 2 -pid $(pgrep -x Symbiodock) -stats pid,cpu | grep -E "^[0-9]" | tail -5
log show --last 1m --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "system"' --style compact | tail -3
pkill -x Symbiodock
```

Expected: 0.0 on every line with the island closed, and no `measuring` line in the log: nothing is measured while the tab is not on screen. The open tab cannot be opened from a script; its cost is on the owner's list, and the reader's own cost is the `read` time above (about 10 ms every 2 s, half a percent of a core).

- [ ] **Step 11: Commit**

```bash
git add Symbiodock docs/superpowers/plans/2026-11-21-system-tab-a.md
git commit -m "feat(system): measure this Mac while the System tab is open" -m "The readers need no permission: host statistics, the graphics driver's registry entry, the SMC's temperature keys and the interface counters. The coordinator observes the island's state, so nothing is measured while the tab is not on screen."
git push origin main
```

---

### Task 6: Record it

**Files:**
- Modify: `CLAUDE.md` (`Durum`, roadmap, "Doğrulanmamış varsayımlar"), `docs/superpowers/specs/2026-11-21-system-tab-design.md` if anything was measured differently, this plan (tick the boxes)

- [ ] **Step 1: Run everything once more**

```bash
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: 800 tests pass, `** BUILD SUCCEEDED **`, and the renders are written. Read `expanded-system.png` and one render of each other tab (`expanded-agents.png`, `expanded-media-volume.png`, `expanded-files.png` or the nearest name in `build/render`) to see that the fourth tab did not disturb their headers.

- [ ] **Step 2: Write the status**

In `CLAUDE.md`:

- Add a `Durum` entry, in Turkish like the others, with what this plan's steps actually showed: the test count; what the renders show; the numbers `SYMBIODOCK_PRINT_SYSTEM` printed and what they were compared with; the read cost in µs; CPU 0 with the island closed; that the open tab's look, the bars' motion, its CPU cost and the values against Activity Monitor are the owner's to check; the demo values `SYMBIODOCK_DEMO_SYSTEM=1|hot` and `SYMBIODOCK_PRINT_SYSTEM=1`; that the `Devices` panel is empty until Part B.
- In the roadmap, leave Faz 12 unticked (Part B is open) and say that Part A's code is done and waits for the owner's check.
- In "Doğrulanmamış varsayımlar", correct the System entry with anything this plan measured differently from the spec.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers
git commit -m "docs: record part A of the System tab" -m "What was measured, what the renders show and what is left for the owner to look at."
git push origin main
```

Then stop and give the owner the list below.

## Elle kontrol listesi

Çalıştır: `open build/Build/Products/Debug/Symbiodock.app`

1. Adanın üstüne gel, sekme şeridinde dört simge var: terminal, çubuklar, çip, kâğıtlar.
2. Çip simgesine tıkla: `System` sekmesi açılıyor, yarım saniye içinde değerler doluyor.
3. CPU, GPU ve RAM satırları kendi renginde (mavi, mor-pembe, yeşil); çubuklar değere göre dolu.
4. Değerler 2 sn'de bir değişiyor; çubuk yeni değere yumuşakça kayıyor, yazılar zıplamıyor.
5. CPU yüzdesi Activity Monitor'ün CPU sekmesiyle yakın (100 − Idle).
6. RAM, Activity Monitor'ün "Memory Used" değeriyle yakın.
7. GPU yüzdesi Activity Monitor → Window → GPU History ile yakın.
8. Sıcaklıklar makul (boşta 40-50 °C). Ağır bir iş başlat: CPU yüzdesi ve sıcaklığı yükseliyor.
9. Bir indirme başlat: `↓` hızı ve grafik yükseliyor; bitince düşüyor.
10. Wi-Fi'yi kapat: `Network` panelinde `Offline`; açınca hızlar geri geliyor.
11. `Devices` panelinde yalnızca başlık ve `—` var (Bölüm B'de dolacak).
12. Başka sekmeye geç ve geri dön: son değerler hemen görünüyor, grafik yeniden başlıyor.
13. Adadan çık, yeniden gel: ada `System`'de değil, her zamanki sekmede açılıyor.
14. Sağ tık → `First tab`: yalnızca `Agents` ve `Media` var.
15. Adayı bir kenara taşı (alt, sağ): `System` sekmesi orada da düzgün görünüyor.
16. Mac'i uyut, uyandır, sekmeyi aç: değerler saçmalamıyor (dev bir hız ya da %100 yok).
17. Activity Monitor'de Symbiodock: sekme açıkken CPU %1 civarı ya da altı, ada kapalıyken %0.
18. Hiçbir izin penceresi çıkmadı.

Beğenmediğin renk, boşluk ya da boyut olursa söyle; taslaktaki ölçüler ayarlanabilir.
