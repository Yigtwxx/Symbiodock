import AppKit

/// A transparent panel that covers a whole display, above the menu bar,
/// and never takes focus.
final class OverlayPanel: NSPanel {
    init(screenFrame: CGRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        // The panel never becomes key; without this no mouse-moved event reaches the
        // local monitor while the pointer is on the island.
        acceptsMouseMovedEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit normally pushes windows below the menu bar; the island must reach the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
