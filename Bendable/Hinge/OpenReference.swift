import Foundation

/// Tracks where "fully open" currently is.
///
/// A fixed open angle is wrong in both directions. Learn it as a maximum and someone
/// who once pushed the lid right back is left permanently short of 1.0, so the effect
/// is already partly applied while they work and the last stretch of travel does
/// nothing. Pin it to a constant and it is wrong for everyone whose posture differs
/// from whoever picked the constant.
///
/// So it follows the lid: wherever the panel comes to rest is what open means. It
/// moves up readily, because opening wider is unambiguous, and down only after a long
/// dwell, so pausing halfway through closing the lid does not quietly cancel the
/// animation.
struct OpenReference: Sendable, Equatable {
    /// The lid has to be at least this far open before it can teach us anything.
    static let minimumSpan = 25.0
    /// Degrees per second under which the lid counts as parked.
    static let stillThreshold = 1.5
    /// Longest gap between samples that still counts as continuous observation.
    ///
    /// This has to clear the sensor's idle cadence. A parked lid emits roughly one
    /// report a second, since it only streams quickly while the angle is changing. A
    /// gate any tighter rejects every reading taken while the lid is still, which is
    /// precisely when the reference is supposed to be learning.
    static let maximumSampleGap: TimeInterval = 3

    /// How long it must stay parked before the reference follows it.
    static let dwellToOpen: TimeInterval = 1.5
    static let dwellToClose: TimeInterval = 6
    /// Time constants for the two directions once the dwell has passed.
    static let riseTime: TimeInterval = 0.3
    static let fallTime: TimeInterval = 3

    private(set) var angle: Double
    private var stillFor: TimeInterval = 0

    init(angle: Double) {
        self.angle = angle
    }

    mutating func reset(to angle: Double) {
        self.angle = angle
        stillFor = 0
    }

    mutating func update(
        angle current: Double,
        degreesPerSecond: Double,
        dt: TimeInterval,
        closedAngle: Double
    ) {
        // A gap in the samples means the lid may have moved unobserved, across sleep
        // for instance, so the dwell has to start again.
        guard dt > 0, dt < Self.maximumSampleGap else {
            stillFor = 0
            return
        }
        guard abs(degreesPerSecond) < Self.stillThreshold else {
            stillFor = 0
            return
        }
        // A shut lid, or one in clamshell, must never become the definition of open.
        guard current >= closedAngle + Self.minimumSpan else {
            stillFor = 0
            return
        }

        stillFor += dt

        if current > angle + 0.5 {
            guard stillFor >= Self.dwellToOpen else { return }
            angle = lerp(angle, current, min(dt / Self.riseTime, 1))
        } else if current < angle - 0.5 {
            guard stillFor >= Self.dwellToClose else { return }
            angle = lerp(angle, current, min(dt / Self.fallTime, 1))
        }
    }
}
