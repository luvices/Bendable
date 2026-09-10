#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Snapshots the menu bar popover to a PNG, so layout changes can be reviewed without
/// clicking through the menu bar. Reachable from `Bendable --render-ui <output.png>`.
///
/// The Metal-backed preview does not survive an AppKit cache capture, so the pane
/// swaps in a still of the same preset while this runs.
@MainActor
enum PopoverSnapshot {
    enum SnapshotError: Error {
        case captureFailed
    }

    /// True while a snapshot is being taken. The preview is a `CAMetalLayer`, which an
    /// AppKit cache capture leaves as a hole; the pane substitutes a still of the same
    /// preset so the picture is of the whole interface rather than most of it.
    private(set) static var isRendering = false

    static func render(to url: URL, tab: PopoverTab = .style) throws {
        isRendering = true
        defer { isRendering = false }
        let coordinator = AppCoordinator()
        // A snapshot process never opens the real sensor, so without this the header
        // would report the machine as having no lid at all. The simulator is the same
        // provider the debug pane uses, so what is drawn is a state the app really has.
        coordinator.useSimulatedHinge(true)
        coordinator.simulator?.emit(angle: 68)
        let host = NSHostingView(rootView: MenuBarView(tab: tab).environment(coordinator))
        // The capture has no window, so nothing supplies an appearance or the popover's
        // own material. Without both, label colours resolve for one appearance and are
        // drawn onto the other, and the result is a picture of nothing.
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()

        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.captureFailed
        }
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: representation) {
            NSGraphicsContext.current = context
            NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
            host.bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        host.cacheDisplay(in: host.bounds, to: representation)

        guard let image = representation.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else { throw SnapshotError.captureFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.captureFailed }
    }
}
#endif
