import AppKit

/// Borderless, click-through, always-on-top window covering one screen.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, contentView: NSView) {
        super.init(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        setFrame(screen.frame, display: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isMovable = false
        displaysWhenScreenProfileChanges = true
        // Above full-screen apps and the Dock, but below the login window and any
        // system alert, so the app can never trap the user.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        animationBehavior = .none
        sharingType = .none

        self.contentView = contentView
        contentView.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Never take focus, even if something tries to make this window key.
    override func makeKey() {}

    func matchGeometry(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
}
