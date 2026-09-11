import Foundation
import IOKit

/// Keeps the Mac running with the lid shut.
///
/// There is no polite way to do this. Every public sleep assertion is documented as
/// not covering the lid: `IOPMLib.h` says of the strongest of them that "the system may
/// still sleep for lid close". The only switch that works is `pmset disablesleep`,
/// which is a system setting and needs root.
///
/// So this asks. Each change puts up the standard macOS authorization dialog, runs one
/// fixed command, and keeps nothing: no helper tool, no daemon, no stored credential,
/// no privilege held between one toggle and the next. That is slower than a helper
/// that would do it silently, and it is the reason Bendable still installs nothing
/// privileged.
///
/// The setting is system-wide and outlives the app. It survives a quit, a crash and a
/// reboot, and turning it off needs authorization exactly as much as turning it on
/// did, so it cannot be quietly cleaned up behind the user. `intent` is how the
/// interface tells a state it asked for from one it has inherited.
enum SleepGuard {
    enum Failure: Error, LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Authorization was cancelled."
            case let .failed(message): message
            }
        }
    }

    /// What the system is actually doing, read straight from the power root.
    ///
    /// Readable without privileges, which matters: the interface must be able to show
    /// the truth even when it has no way to change it.
    static var isSleepDisabled: Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(
            service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0
        )
        guard let value = property?.takeRetainedValue() as? Bool else { return false }
        return value
    }

    /// Puts up the authorization dialog and applies the setting.
    ///
    /// The command is a literal with a single interpolated digit that this file
    /// produces itself. Nothing from the user, from a preference or from the network
    /// reaches the shell.
    @MainActor
    static func setSleepDisabled(_ disabled: Bool) throws {
        let source = """
        do shell script "/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)" \
        with administrator privileges
        """
        guard let script = NSAppleScript(source: source) else {
            throw Failure.failed("Could not build the authorization request.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return }
        // -128 is the user closing the dialog, which is an answer rather than a fault.
        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -128 {
            throw Failure.cancelled
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        throw Failure.failed(message ?? "The setting could not be changed.")
    }
}

/// How a switch that Bendable does not exclusively own should read.
///
/// The setting is global. Another app, or the user at a terminal, can change it while
/// Bendable is running, and Bendable can be quit or killed while it is on. Rather than
/// assume, the interface compares what it asked for against what is true.
enum SleepGuardStatus: Equatable {
    /// Off, and nobody asked for it.
    case off
    /// On, and Bendable is the one that asked.
    case on
    /// Bendable asked for it and something has since turned it off.
    case revokedElsewhere
    /// On without Bendable asking: a previous run that was killed, another app, or a
    /// terminal. Worth saying out loud, because the Mac will not sleep on lid close
    /// and nothing on screen would otherwise explain why.
    case onFromElsewhere

    static func resolve(intent: Bool, actual: Bool) -> SleepGuardStatus {
        switch (intent, actual) {
        case (false, false): .off
        case (true, true): .on
        case (true, false): .revokedElsewhere
        case (false, true): .onFromElsewhere
        }
    }

    /// True when the Mac will stay up with the lid shut, whoever asked for it.
    var isActive: Bool {
        self == .on || self == .onFromElsewhere
    }
}
