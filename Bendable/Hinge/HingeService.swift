import Foundation

/// Owns the active provider and publishes normalized state on the main actor.
///
/// Provider callbacks arrive on the sensor's own queue; normalization is cheap and
/// allocation-free, so it runs there and only the finished `HingeState` is hopped to
/// the main actor. That keeps sensor-to-render latency to a single queue hop.
@MainActor
final class HingeService {
    private(set) var capability: HingeCapability = .unsupported
    private(set) var state: HingeState = .open
    /// Last unfiltered reading, for the Advanced pane.
    private(set) var rawAngle: Double?
    private(set) var updateRate: Double = 0

    var onStateChange: ((HingeState) -> Void)?

    private var provider: HingeProvider?
    private let pipeline = Pipeline()
    private let mailbox = Mailbox()
    private var isRunning = false

    var calibration: HingeCalibration {
        get { pipeline.calibration }
        set { pipeline.calibration = newValue }
    }

    var smoothing: Double {
        get { pipeline.smoothing }
        set { pipeline.smoothing = newValue }
    }

    var animationStartAngle: Double {
        get { pipeline.animationStartAngle }
        set { pipeline.animationStartAngle = newValue }
    }

    /// The band the animation runs over, for the diagnostics and the presets.
    var animationRange: ClosedRange<Double> { pipeline.animationRange }

    /// Chooses the best provider this Mac supports. Injectable for tests and the debug panel.
    static func makeProvider() -> HingeProvider? {
        if LidAngleSensorProvider.isAvailable() { return LidAngleSensorProvider() }
        if LidStateProvider.isAvailable() { return LidStateProvider() }
        return nil
    }

    func start(provider injected: HingeProvider? = nil) {
        guard !isRunning else { return }
        guard let selected = injected ?? Self.makeProvider() else {
            capability = .unsupported
            Log.hinge.notice("No hinge provider available on this Mac")
            return
        }

        if attach(selected) { return }

        // Fail open: if the preferred provider refuses to start, fall back to the
        // discrete lid-state path rather than leaving the app inert.
        if !(selected is LidStateProvider), attach(LidStateProvider()) { return }
        capability = .unsupported
    }

    @discardableResult
    private func attach(_ candidate: HingeProvider) -> Bool {
        // Built once, outside the sensor callback, so the weak capture lives in a
        // single @Sendable closure rather than being re-formed per sample.
        let deliver: @Sendable () -> Void = { [weak self, mailbox] in
            MainActor.assumeIsolated {
                guard let self, let latest = mailbox.collect() else { return }
                self.apply(latest)
            }
        }

        do {
            try candidate.start { [pipeline, mailbox] sample in
                guard let update = pipeline.ingest(sample) else { return }
                // Coalesce rather than queue. Creating a Task per sample allocates at
                // the sensor's rate and, worse, lets a backlog build up so the frame
                // being drawn describes an angle the lid has already left. Only the
                // newest reading is ever worth having.
                guard mailbox.deposit(update) else { return }
                DispatchQueue.main.async(execute: deliver)
            }
        } catch {
            Log.hinge.error(
                "Provider \(String(describing: type(of: candidate)), privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        provider = candidate
        capability = candidate.capability
        isRunning = true
        Log.hinge.info("Hinge capability: \(self.capability.rawValue, privacy: .public)")
        return true
    }

    func stop() {
        provider?.stop()
        provider = nil
        isRunning = false
        pipeline.reset()
        mailbox.clear()
    }

    func reconnect() {
        provider?.reconnect()
        pipeline.reset()
    }

    func resetCalibration() {
        pipeline.calibration = .default
        pipeline.reset()
    }

    private func apply(_ update: Pipeline.Update) {
        rawAngle = update.rawAngle
        updateRate = update.rate
        guard update.state != state else { return }
        state = update.state
        onStateChange?(update.state)
    }

    /// Holds the newest pending update, and says whether a delivery is already on its
    /// way so callers do not schedule a second one.
    private final class Mailbox: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: Pipeline.Update?
        private var isScheduled = false

        /// Returns true when the caller should schedule a delivery.
        func deposit(_ update: Pipeline.Update) -> Bool {
            lock.withLock {
                pending = update
                guard !isScheduled else { return false }
                isScheduled = true
                return true
            }
        }

        func collect() -> Pipeline.Update? {
            lock.withLock {
                isScheduled = false
                defer { pending = nil }
                return pending
            }
        }

        func clear() {
            lock.withLock {
                pending = nil
                isScheduled = false
            }
        }
    }

    /// Thread-safe wrapper around the value-type normalizer.
    private final class Pipeline: @unchecked Sendable {
        struct Update: Sendable {
            var state: HingeState
            var rawAngle: Double?
            var rate: Double
        }

        private let lock = NSLock()
        private var normalizer = HingeNormalizer()
        private var lastTimestamp: TimeInterval?
        private var smoothedRate: Double = 0

        var calibration: HingeCalibration {
            get { lock.withLock { normalizer.calibration } }
            set { lock.withLock { normalizer.calibration = newValue } }
        }

        var smoothing: Double {
            get { lock.withLock { normalizer.smoothing } }
            set { lock.withLock { normalizer.smoothing = newValue } }
        }

        var animationStartAngle: Double {
            get { lock.withLock { normalizer.animationStartAngle } }
            set { lock.withLock { normalizer.animationStartAngle = newValue } }
        }

        var animationRange: ClosedRange<Double> {
            lock.withLock { normalizer.animationRange }
        }

        func reset() {
            lock.withLock {
                normalizer.reset()
                lastTimestamp = nil
                smoothedRate = 0
            }
        }

        func ingest(_ sample: HingeSample) -> Update? {
            lock.withLock {
                guard let state = normalizer.normalize(sample) else { return nil }
                if let previous = lastTimestamp, sample.timestamp > previous {
                    let instantaneous = 1 / (sample.timestamp - previous)
                    smoothedRate = smoothedRate == 0 ? instantaneous
                        : lerp(smoothedRate, instantaneous, 0.2)
                }
                lastTimestamp = sample.timestamp
                return Update(state: state, rawAngle: sample.angle, rate: smoothedRate)
            }
        }
    }
}
