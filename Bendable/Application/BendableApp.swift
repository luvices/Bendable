import AppKit
import SwiftUI

/// Plain `NSApplication` rather than a SwiftUI `App`: the only window this app has is
/// a status item popover, and SwiftUI's `MenuBarExtra` gives no control over how that
/// window is sized or placed.
@main
enum BendableMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        // `NSApplication.delegate` is weak, so the delegate has to be owned for the
        // lifetime of the run loop.
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var menuBar: MenuBarController?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock tile, no Cmd-Tab entry.
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        if PresetSheetRenderer.handleCommandLine() {
            NSApp.terminate(nil)
            return
        }
        #endif

        coordinator.start()
        menuBar = MenuBarController(coordinator: coordinator)

        if !coordinator.preferences.hasCompletedFirstRun {
            showWelcome()
        }

        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--trace-close") {
            let seconds = CommandLine.arguments.dropFirst(index + 1).first.flatMap(Double.init) ?? 0.7
            Task { @MainActor in
                let report = await CloseTrace.run(
                    coordinator: coordinator, closeDuration: seconds
                ) + "\n"
                FileHandle.standardError.write(Data(report.utf8))
                NSApp.terminate(nil)
            }
            return
        }

        if CommandLine.arguments.contains("--open-popover") {
            // The status item is not laid out until the run loop has turned, and
            // `NSPopover.show` against a button that is not on screen yet does nothing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.menuBar?.openForInspection()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                // stdout is block buffered and `terminate` does not flush it.
                let report = (self?.menuBar?.inspectionReport() ?? "no menu bar") + "\n"
                FileHandle.standardError.write(Data(report.utf8))
                if CommandLine.arguments.contains("--exit-after") {
                    NSApp.terminate(nil)
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func showWelcome() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: WelcomeView(onDone: { [weak self] in
                self?.welcomeWindow?.close()
                self?.welcomeWindow = nil
            })
            .environment(coordinator)
        )
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
