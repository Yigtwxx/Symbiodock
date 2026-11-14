// Prints every on-screen window owned by Symbiodock: its window level and bounds.
// Usage: swift scripts/list-windows.swift
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
    as? [[String: Any]] ?? []

for window in windows where window[kCGWindowOwnerName as String] as? String == "Symbiodock" {
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func value(_ key: String) -> Int { Int(bounds[key] as? Double ?? -1) }
    print("layer=\(layer) x=\(value("X")) y=\(value("Y")) w=\(value("Width")) h=\(value("Height"))")
}
