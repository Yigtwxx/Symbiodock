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
