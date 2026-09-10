import Foundation

/// Turns validated raw samples into the smoothed, calibrated state the rest of the app sees.
///
/// Kept as a plain struct with no I/O so the whole sensor → animation contract can be
/// exercised deterministically in tests.
struct HingeNormalizer {
    /// Below this normalized openness the lid counts as shut for state-machine purposes.
    static let closedProgressThreshold = 0.02
    /// Progress-per-second below which motion is reported as `.still`.
    static let stillVelocityThreshold = 0.02

    /// The open end lives in `reference`, which follows the lid; only the floor is
    /// stored here. Rebuilding the value on demand keeps the two from fighting, since an
    /// earlier version wrote the reference back into a stored calibration every sample,
    /// whose `didSet` then reset the very dwell timer that drives it.
    var calibration: HingeCalibration {
        get { HingeCalibration(closedAngle: closedAngle, openAngle: reference.angle) }
        set {
            closedAngle = newValue.closedAngle
            reference.reset(to: newValue.openAngle)
        }
    }

    var autoCalibrates: Bool

    /// Degrees above closed at which the animation starts. See `HingeCalibration`.
    var animationStartAngle: Double = HingeCalibration.defaultStartAngle

    /// The band the animation actually runs over, after the resting angle has had its
    /// say. Published for the diagnostics and for the presets' 1:1 tilt.
    var animationRange: ClosedRange<Double> {
        calibration.animationRange(startAngle: animationStartAngle)
    }

    /// 0 = no filtering, 1 = maximum. Scales the filter's responsiveness term.
    var smoothing: Double {
        didSet { applySmoothing() }
    }

    /// Time constant for the velocity used to decide travel direction.
    ///
    /// Differentiating at the sensor's rate amplifies dither no matter how well the
    /// angle itself is filtered, so the direction decision runs off its own averaged
    /// rate. Roughly a tenth of a second is short next to any real lid movement and
    /// long enough to cancel symmetric sensor noise. The reported velocity stays
    /// unaveraged, because the fold's look-ahead needs the true instantaneous rate.
    private static let directionTimeConstant = 0.09

    private var filter = OneEuroFilter()
    private var fit = AngularFit()
    private var closedAngle: Double
    private var reference: OpenReference
    private var lastState: HingeState?
    private var lastDirection: HingeDirection = .still
    private var directionVelocity: Double = 0
    private var lastTimestamp: TimeInterval?

    init(calibration: HingeCalibration = .default, smoothing: Double = 0.25, autoCalibrates: Bool = true) {
        self.closedAngle = calibration.closedAngle
        self.reference = OpenReference(angle: calibration.openAngle)
        self.smoothing = smoothing
        self.autoCalibrates = autoCalibrates
        applySmoothing()
    }

    private mutating func applySmoothing() {
        let s = clamp(smoothing, 0, 1)
        // More smoothing lowers the resting cutoff (steadier) and lowers beta
        // (less eager to open up during motion). The floor keeps hand-speed
        // movement essentially unfiltered even at maximum smoothing.
        // Firm while the lid is parked, so dither across a degree boundary does not
        // reach the screen; wide open the moment it moves, so nothing is delayed. The
        // speed term is fed a properly measured rate, which is what makes this work at
        // all. The filter's own derivative could never tell dither from movement.
        filter.minCutoff = lerp(4.0, 0.8, s)
        filter.beta = lerp(2.4, 0.9, s)
    }

    mutating func reset() {
        filter.reset()
        fit.reset()
        reference.reset(to: reference.angle)
        lastState = nil
        lastDirection = .still
        directionVelocity = 0
        lastTimestamp = nil
    }

    /// Returns `nil` when the sample carries nothing usable.
    mutating func normalize(_ sample: HingeSample) -> HingeState? {
        guard let rawAngle = sample.angle else {
            return normalizeLidStateOnly(sample)
        }
        guard rawAngle.isFinite, HingeCalibration.plausibleRange.contains(rawAngle) else {
            Log.trace(Log.hinge, "rejected implausible angle \(rawAngle)")
            return lastState
        }

        if autoCalibrates, HingeCalibration.plausibleRange.contains(rawAngle) {
            closedAngle = min(closedAngle, rawAngle)
        }

        // The reading is a whole number of degrees, so on its own it can only ever
        // climb a staircase. The fit places a line through the last several readings and
        // evaluates it now, which recovers where between two degrees the lid actually
        // is. The result is held to within one degree of the reading, so it stays an
        // estimate of the lid rather than an extrapolation away from it.
        let estimate = fit.update(angle: rawAngle, at: sample.timestamp)
        let degreesPerSecond = estimate.degreesPerSecond
        let angle = filter.apply(
            estimate.angle, at: sample.timestamp, speed: degreesPerSecond
        )

        if autoCalibrates {
            reference.update(
                angle: angle, degreesPerSecond: degreesPerSecond,
                dt: lastTimestamp.map { sample.timestamp - $0 } ?? 0,
                closedAngle: closedAngle
            )
        }

        let range = animationRange
        let progress = calibration.progress(for: angle, startAngle: animationStartAngle)

        // Convert the filtered angular rate into progress units so downstream code
        // never has to know the calibrated span. Taken from the animation band, not the
        // whole travel, and deliberately not clamped the way progress is, so a lid
        // moving above the band still reports that it is moving. That is what lets the
        // desktop still be fetched before the effect is due to start.
        let span = max(range.upperBound - range.lowerBound, 1)
        let velocity = degreesPerSecond / span

        var reportInterval: TimeInterval = 0
        if let previousTimestamp = lastTimestamp, sample.timestamp > previousTimestamp {
            let dt = sample.timestamp - previousTimestamp
            reportInterval = dt
            directionVelocity = lerp(directionVelocity, velocity, dt / (Self.directionTimeConstant + dt))
        } else if lastTimestamp == nil {
            directionVelocity = velocity
        }
        lastTimestamp = sample.timestamp

        let direction = Self.direction(velocity: directionVelocity, previous: lastDirection)
        lastDirection = direction

        let state = HingeState(
            angle: angle,
            progress: progress,
            velocity: velocity,
            direction: direction,
            isClosed: progress <= Self.closedProgressThreshold || !sample.lidIsOpen,
            timestamp: sample.timestamp,
            reportInterval: reportInterval
        )
        lastState = state
        return state
    }

    /// Fallback path: synthesize progress from a discrete open/closed edge.
    private mutating func normalizeLidStateOnly(_ sample: HingeSample) -> HingeState? {
        let progress: Double = sample.lidIsOpen ? 1 : 0
        let previous = lastState?.progress ?? progress
        let direction: HingeDirection =
            progress > previous ? .opening : (progress < previous ? .closing : .still)
        lastDirection = direction
        lastTimestamp = sample.timestamp

        let state = HingeState(
            angle: nil,
            progress: progress,
            velocity: 0,
            direction: direction,
            isClosed: !sample.lidIsOpen,
            timestamp: sample.timestamp,
            reportInterval: 0
        )
        lastState = state
        return state
    }

    private static func direction(velocity: Double, previous: HingeDirection) -> HingeDirection {
        if velocity > stillVelocityThreshold { return .opening }
        if velocity < -stillVelocityThreshold { return .closing }
        // Hysteresis: hold the previous direction through the dead band so a slow,
        // steady pull does not flicker between `.closing` and `.still`.
        return abs(velocity) > stillVelocityThreshold / 2 ? previous : .still
    }
}
