import Foundation

/// What the current machine can actually tell us about its lid.
enum HingeCapability: String, Sendable, Equatable, CaseIterable {
    /// A lid angle sensor is present and streaming degrees.
    case continuousAngle
    /// Only open/closed transitions are observable.
    case lidStateOnly
    /// Not a laptop, or nothing usable was found.
    case unsupported

    var localizedDescription: String {
        switch self {
        case .continuousAngle: "Continuous hinge angle"
        case .lidStateOnly: "Lid open/close events only"
        case .unsupported: "No lid detected"
        }
    }

    var explanation: String {
        switch self {
        case .continuousAngle:
            "Animations follow the physical hinge angle in real time."
        case .lidStateOnly:
            "This Mac reports only that the lid opened or closed, so animations play on a timeline instead of tracking the hinge."
        case .unsupported:
            "Bendable found no built-in lid on this Mac. Use the preview below to try the animations."
        }
    }
}

enum HingeDirection: String, Sendable, Equatable {
    case opening
    case closing
    case still
}

/// A raw provider reading, before validation, calibration or filtering.
struct HingeSample: Sendable, Equatable {
    /// Degrees between base and lid, or `nil` when the provider only knows open/closed.
    var angle: Double?
    var lidIsOpen: Bool
    var timestamp: TimeInterval

    init(angle: Double?, lidIsOpen: Bool, timestamp: TimeInterval = MonotonicClock.now()) {
        self.angle = angle
        self.lidIsOpen = lidIsOpen
        self.timestamp = timestamp
    }
}

/// The application-facing hinge state. Everything above the hinge layer consumes only this.
struct HingeState: Sendable, Equatable {
    /// Filtered angle in degrees when a real sensor is present.
    var angle: Double?
    /// 1 = fully open, 0 = closed.
    var progress: Double
    /// Change in `progress` per second. Negative while closing.
    var velocity: Double
    var direction: HingeDirection
    var isClosed: Bool
    var timestamp: TimeInterval
    /// How long it has been since the previous reading.
    ///
    /// Readings land a whole degree apart, so this is a direct measure of how fast the
    /// lid is moving and of how long the reading in hand stays worth acting on. A slow
    /// lid is not a stopped lid.
    var reportInterval: TimeInterval = 0

    static let open = HingeState(
        angle: nil, progress: 1, velocity: 0, direction: .still, isClosed: false, timestamp: 0
    )
}
