import Foundation
import os

enum Log {
    private static let subsystem = "com.bendable.app"

    static let hinge = Logger(subsystem: subsystem, category: "hinge")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let animation = Logger(subsystem: subsystem, category: "animation")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Verbose tracing is opt-in so release builds stay quiet. Enable with
    /// `defaults write com.bendable.app debugLogging -bool YES`.
    static var verboseEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "debugLogging") }
        set { UserDefaults.standard.set(newValue, forKey: "debugLogging") }
    }

    static func trace(_ logger: Logger, _ message: @autoclosure () -> String) {
        guard verboseEnabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }
}
