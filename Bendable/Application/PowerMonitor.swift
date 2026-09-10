import AppKit
import Foundation

/// System power and session events that matter to the overlay.
enum PowerEvent: String, Sendable, Equatable, CaseIterable {
    case systemWillSleep
    case systemDidWake
    case displaysDidSleep
    case displaysDidWake
    case screenLocked
    case screenUnlocked
}

/// Bridges the workspace and distributed notification centres into one stream.
///
/// Bendable never takes a power assertion and never delays a sleep transition; it
/// only observes. If it misses an event the worst outcome is a stale overlay, which
/// the hinge pipeline clears on the next reading.
@MainActor
final class PowerMonitor {
    var onEvent: ((PowerEvent) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let mapping: [(NotificationCenter, Notification.Name, PowerEvent)] = [
            (workspace, NSWorkspace.willSleepNotification, .systemWillSleep),
            (workspace, NSWorkspace.didWakeNotification, .systemDidWake),
            (workspace, NSWorkspace.screensDidSleepNotification, .displaysDidSleep),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaysDidWake),
        ]
        for (center, name, event) in mapping {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit(event) }
            })
        }

        let distributed = DistributedNotificationCenter.default()
        let lockMapping: [(String, PowerEvent)] = [
            ("com.apple.screenIsLocked", .screenLocked),
            ("com.apple.screenIsUnlocked", .screenUnlocked),
        ]
        for (name, event) in lockMapping {
            observers.append(distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit(event) }
            })
        }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Used by the debug panel to exercise the state machine without real power events.
    func emit(_ event: PowerEvent) {
        Log.trace(Log.power, "event \(event.rawValue)")
        onEvent?(event)
    }

    /// Cleanup is explicit via `stop()`; the monitor is owned for the app's lifetime.
}
