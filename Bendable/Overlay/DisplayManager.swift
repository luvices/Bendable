import AppKit
import CoreGraphics

/// Finds the display that physically moves with the lid.
enum DisplayManager {
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let id = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
    }
}
