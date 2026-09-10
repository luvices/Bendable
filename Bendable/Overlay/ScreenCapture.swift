import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Grabs a single still of the built-in display.
///
/// A still is enough: by the time the overlay appears the lid is already moving, and
/// a one-shot capture avoids running a capture stream, and paying its power cost, for
/// the entire life of the app.
@MainActor
final class ScreenCapture {
    enum Availability {
        case granted
        case denied
        case unavailable
    }

    private var cachedContent: SCShareableContent?
    private var cacheTimestamp: TimeInterval = 0
    /// Long, because the list only changes when the display configuration does, and
    /// `OverlayCoordinator` invalidates this explicitly when that happens. A short
    /// lifetime meant most closes paid for a cold cross-process query.
    private let cacheLifetime: TimeInterval = 600

    /// Checks the TCC state without triggering a prompt.
    static var permissionState: Availability {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Shows the system prompt. Only call this from an explicit user action.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Pre-warms the shareable-content list so the capture at the start of a close is
    /// not paying for a cold cross-process query.
    func prewarm() {
        guard CGPreflightScreenCaptureAccess() else { return }
        Task { _ = try? await shareableContent() }
    }

    func captureBuiltInDisplay() async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let screen = DisplayManager.builtInScreen(),
              let displayID = DisplayManager.displayID(of: screen)
        else { return nil }

        do {
            let content = try await shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            // Bendable's own overlay must never appear in its own capture.
            let ownWindows = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
            }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

            let configuration = SCStreamConfiguration()
            // `SCDisplay` reports points; the still has to be native pixels or the
            // desktop is upscaled back onto a Retina panel and looks soft.
            configuration.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
            configuration.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.scalesToFit = false
            // The default is `.automatic`, which is free to hand back something smaller.
            configuration.captureResolution = .best
            configuration.colorSpaceName = CGColorSpace.sRGB

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            )
            Log.trace(
                Log.capture,
                "captured \(image.width)x\(image.height) for a \(display.width)x\(display.height) pt display at \(screen.backingScaleFactor)x"
            )
            return image
        } catch {
            Log.capture.error("Capture failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        let now = MonotonicClock.now()
        if let cachedContent, now - cacheTimestamp < cacheLifetime {
            return cachedContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        cachedContent = content
        cacheTimestamp = now
        return content
    }

    func invalidateCache() {
        cachedContent = nil
    }
}
