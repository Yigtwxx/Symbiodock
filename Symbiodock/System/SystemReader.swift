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
        // The counters are divided by the time between two dates, so they are read right
        // beside the date; the temperatures take the longest and come last.
        let date = Date()
        let counters = NetworkCounterReader.counters(store: store)
        let cpu = HostSampler.cpuTicks()
        return SystemReading(
            date: date, cpu: cpu, memory: HostSampler.memory(), gpu: GPUProbe.utilization(),
            temperatures: withTemperatures ? temperatures() : nil, counters: counters)
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
