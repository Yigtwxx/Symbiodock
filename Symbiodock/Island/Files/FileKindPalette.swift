import SwiftUI
import SymbiodockCore

/// The colour and the plain name of each kind of file. The colours are the ones the
/// shelf's bubble uses too, so a tile and the bubble agree.
enum FileKindPalette {
    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    static func color(_ kind: FileKind) -> Color {
        switch kind {
        case .image: hex(0x32ADE6)
        case .pdf: hex(0xFF453A)
        case .document: hex(0x0A84FF)
        case .audio: hex(0xFF375F)
        case .video: hex(0x5E5CE6)
        case .archive: hex(0xFF9F0A)
        case .folder: hex(0x64D2FF)
        case .other: hex(0x8E8E93)
        }
    }

    /// "Image", "PDF": what the detail line calls the kind.
    static func name(_ kind: FileKind) -> String {
        switch kind {
        case .image: "Image"
        case .pdf: "PDF"
        case .document: "Document"
        case .audio: "Audio"
        case .video: "Video"
        case .archive: "Archive"
        case .folder: "Folder"
        case .other: "File"
        }
    }
}
