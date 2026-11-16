import Foundation

/// What the Files tab asks of the app.
public enum FileRequest: Equatable, Sendable {
    /// Every listed file that offers that chip.
    case convert([UUID], label: String)
    case cancel([UUID])
    case reveal([UUID])
    case remove([UUID])
    /// The stack's id: its files become lone tiles.
    case unstack(UUID)
}

/// A conversion in flight for one item.
public struct FileConversion: Equatable, Sendable {
    public var label: String
    public var started: Date
    /// Set once the work is over and the tile is changing under the closed cocoon.
    public var revealStarted: Date?

    public init(label: String, started: Date, revealStarted: Date? = nil) {
        self.label = label
        self.started = started
        self.revealStarted = revealStarted
    }
}

/// How a conversion ended.
public enum ConversionResult: Equatable, Sendable {
    case converted(url: URL, isDirectory: Bool), failed(String), cancelled
}

/// A short message about one item, shown until the person moves on.
public struct ShelfNotice: Equatable, Sendable {
    public var id: UUID
    public var text: String

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}
