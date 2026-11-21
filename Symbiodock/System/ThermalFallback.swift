import Foundation
import IOKit
import SymbiodockCore

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
            if TemperatureKeys.validRange.contains(value) { readings.append(value) }
        }
        return readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
    }
}
