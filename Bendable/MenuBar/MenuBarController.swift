import AppKit
import SwiftUI

/// Owns the status item and the popover.
///
/// This is deliberately plain AppKit rather than `MenuBarExtra`. The SwiftUI scene
/// sizes its window from whatever the content asks for and positions it itself, which
/// leaves no way to correct either. An `NSPopover` anchors to the button's own bounds
/// and follows the hosting controller's preferred size.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    private let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let controller = NSHostingController(rootView: MenuBarView().environment(coordinator))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Bendable")
        }
        refreshIcon()
    }

    /// The icon carries one bit beyond "Bendable is running": whether the Mac has been
    /// told not to sleep with the lid shut. That outlives the popover and the app, so
    /// it should not take a click to discover.
    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let awake = coordinator.state.sleepGuard.isActive
        let symbol = awake ? "laptopcomputer.trianglebadge.exclamationmark" : "laptopcomputer"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bendable")
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Bendable")
        image?.isTemplate = true
        button.image = image
        // A status item with neither image nor title is zero width and invisible, and
        // an invisible menu bar item is indistinguishable from an app that did not
        // start. Symbol names can go missing across releases, so never rely on one.
        button.title = image == nil ? "Bendable" : ""
        button.toolTip = awake
            ? "Bendable: your Mac will not sleep with the lid shut"
            : "Bendable"
    }

    #if DEBUG
    /// Opens the popover without a click, so a launch can be inspected from a script.
    func openForInspection() {
        if !popover.isShown { togglePopover() }
    }

    /// Where the status item and the popover actually landed. Read a turn after
    /// opening: the popover's window does not exist until the run loop comes back.
    func inspectionReport() -> String {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            return "no status item button"
        }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var lines = [
            "status item: " + Self.describe(buttonFrame),
            "popover shown: \(popover.isShown)",
            "content size: \(Self.describe(CGRect(origin: .zero, size: popover.contentSize)))",
        ]
        if let popoverFrame = popover.contentViewController?.view.window?.frame {
            lines.append("popover: " + Self.describe(popoverFrame))
            lines.append(String(format: "centre offset: %.1f pt", popoverFrame.midX - buttonFrame.midX))
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ rect: NSRect) -> String {
        String(
            format: "x %.0f y %.0f w %.0f h %.0f",
            rect.origin.x, rect.origin.y, rect.width, rect.height
        )
    }
    #endif

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Opening the popover is the moment the user is most likely to have just
        // changed something in System Settings.
        coordinator.refreshScreenCapturePermission()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The popover is transient and the app is an accessory, so it needs to be made
        // key explicitly or its controls will not accept the first click.
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
