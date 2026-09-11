import Foundation
import Observation

/// Everything the UI observes. Written only by `AppCoordinator`.
@MainActor
@Observable
final class AppState {
    var capability: HingeCapability = .unsupported
    var phase: LidPhase = .idle
    var hinge: HingeState = .open
    var rawAngle: Double?
    var sensorRate: Double = 0
    var frameInterval: Double = 0
    var screenCaptureGranted = false
    /// True when the chosen preset needs the desktop image and cannot have it, so the
    /// engine is quietly rendering something else. The interface has to say so.
    var isSubstitutingPreset = false
    var launchAtLoginEnabled = false
    /// Whether the Mac will stay running with the lid shut, and who asked for it.
    var sleepGuard: SleepGuardStatus = .off
    /// Set when changing that failed, so the popover can say why.
    var sleepGuardProblem: String?
    /// Set when registering a login item failed, so the popover can say why.
    var launchAtLoginProblem: String?
    var calibration: HingeCalibration = .default
    /// The band the animation actually runs over, which is not the whole travel.
    var animationRange: ClosedRange<Double> = 0...HingeCalibration.defaultStartAngle

    var framesPerSecond: Double {
        frameInterval > 0 ? 1 / frameInterval : 0
    }

    var normalizedAngle: Double {
        hinge.progress
    }
}
