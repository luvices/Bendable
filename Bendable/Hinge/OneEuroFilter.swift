import Foundation

/// One Euro filter (Casiez, Roussel & Vogel, 2012).
///
/// A fixed low-pass either lags during fast movement or leaves jitter at rest.
/// This one raises its own cutoff with measured speed, which is exactly the
/// tradeoff a hinge needs: rock steady when the lid is parked, and effectively
/// transparent when it is being moved by hand.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double

    private var lastValue: Double?
    private var lastRawValue: Double = 0
    private var lastTimestamp: TimeInterval?

    init(minCutoff: Double = 1.0, beta: Double = 0.35) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func reset() {
        lastValue = nil
        lastRawValue = 0
        lastTimestamp = nil
    }

    /// Filtered value, using an externally measured speed to set the cutoff.
    ///
    /// The filter's own derivative is worthless on a signal quantised to whole degrees,
    /// and the cutoff is exactly what it was for. Given a rate measured properly, this
    /// does what the filter is actually good at: near-transparent while the lid moves,
    /// firm while it sits still and dithers across a degree boundary.
    mutating func apply(
        _ value: Double, at timestamp: TimeInterval, speed: Double
    ) -> Double {
        guard let previous = lastValue, let previousTime = lastTimestamp else {
            lastValue = value
            lastRawValue = value
            lastTimestamp = timestamp
            return value
        }
        let dt = timestamp - previousTime
        guard dt > 0 else { return previous }

        let cutoff = minCutoff + beta * abs(speed)
        let filtered = Self.lowPass(
            value, previous: previous, alpha: Self.alpha(cutoff: cutoff, rate: 1 / dt)
        )
        lastValue = filtered
        lastRawValue = value
        lastTimestamp = timestamp
        return filtered
    }

    private static func alpha(cutoff: Double, rate: Double) -> Double {
        let tau = 1 / (2 * .pi * max(cutoff, 0.0001))
        let te = 1 / rate
        return 1 / (1 + tau / te)
    }

    private static func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}
