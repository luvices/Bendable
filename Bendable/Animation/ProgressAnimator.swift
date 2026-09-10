import Foundation

/// Carries the animation between sensor readings.
///
/// The lid angle sensor reports whole degrees, so a reading can land a display refresh
/// or several apart depending on how fast the lid is moving. Rendering straight from
/// them holds the image still and then steps it. This eases toward the newest reading
/// instead, so the movement is spread across the frames between one and the next.
///
/// It never goes past the reading. An earlier version predicted ahead using the
/// measured rate, which does produce smoother motion while the lid is moving evenly,
/// and also means that letting go of the lid leaves the animation still running: a
/// prediction has no way to know the movement has stopped. Overshoot was a worse fault
/// than the stepping it cured. An exponential approach cannot overshoot by
/// construction, so the error is bounded by how stale the reading is.
struct ProgressAnimator {
    /// The easing is stretched to cover the gap between readings rather than arriving
    /// early and waiting, which would be the stepping back again. Half the interval
    /// puts it most of the way there as the next one lands.
    ///
    /// That proportion is what keeps this honest. The lag of an exponential approach is
    /// its time constant times the rate, and one report is one degree, so easing over
    /// half an interval leaves the picture about half a degree of lid behind whatever
    /// speed the lid is moved at. The floor only bites when readings arrive faster than
    /// a frame, where it is held to roughly one refresh.
    static let minimumEase = 0.012
    static let maximumEase = 0.25

    /// A gap longer than this is a stall, not a frame: snap rather than sweep.
    static let maximumFrameInterval = 0.25

    static func easeTime(forReportInterval interval: TimeInterval) -> TimeInterval {
        clamp(interval * 0.5, minimumEase, maximumEase)
    }

    /// With the angle arriving every frame and already resolved below a degree, the
    /// easing has almost nothing left to do. A frame's worth, to take the edge off.
    static let denseSampleEase = 0.02

    private(set) var value: Double

    init(value: Double = 1) {
        self.value = value
    }

    mutating func reset(to value: Double) {
        self.value = clamp(value, 0, 1)
    }

    /// - Parameters:
    ///   - target: the newest reading, in progress units.
    ///   - reportInterval: how often the sensor is currently speaking, which sets how
    ///     long the easing is given.
    @discardableResult
    mutating func advance(
        target: Double,
        dt: TimeInterval,
        reportInterval: TimeInterval = 0
    ) -> Double {
        guard dt > 0, dt <= Self.maximumFrameInterval else {
            value = clamp(target, 0, 1)
            return value
        }
        let ease = Self.easeTime(forReportInterval: reportInterval)
        value += (target - value) * (1 - exp(-dt / ease))
        value = clamp(value, 0, 1)
        return value
    }

    /// True once the rendered value has caught up, which is when the display link can
    /// be left to idle.
    func hasSettled(at target: Double) -> Bool {
        abs(value - target) < 0.0005
    }
}
