import Foundation

/// Per-machine mapping from sensor degrees to normalized openness.
///
/// Lid angle sensors do not agree on where "closed" sits; a small positive resting
/// angle is common. The comfortable open angle differs by model, by user and by hour of
/// the day. So the closed end is a hardware floor learned from the lowest reading ever
/// seen, and the open end is maintained by `OpenReference`, which follows wherever the
/// lid actually rests.
struct HingeCalibration: Sendable, Equatable, Codable {
    /// Angle at which the lid is physically shut.
    var closedAngle: Double
    /// Where the lid rests when open, learned by `OpenReference`.
    ///
    /// This is *not* where the animation begins. Running the effect over the whole
    /// travel from here means every small adjustment of the lid moves the picture, and
    /// the interesting part, the panel actually turning away, is spread so thin it reads
    /// as a slow dim. The animation lives in `animationRange`, a band just above closed;
    /// above that band progress stays pinned at 1 and nothing happens at all.
    var openAngle: Double

    /// Degrees above closed at which the animation starts, when the lid rests high
    /// enough to allow it.
    static let defaultStartAngle = 45.0

    /// The band can never take more than this share of the travel, or someone who
    /// works with the lid barely open would find the effect already applied at rest.
    static let maximumBandFraction = 0.75

    static let `default` = HingeCalibration(closedAngle: 0, openAngle: 95)

    /// Where the animation actually begins, given a requested start angle.
    func animationRange(startAngle: Double) -> ClosedRange<Double> {
        let travel = max(openAngle - closedAngle, 1)
        let band = min(max(startAngle, 5), travel * Self.maximumBandFraction)
        return closedAngle...(closedAngle + band)
    }

    /// Angles outside this band are treated as sensor noise rather than motion.
    static let plausibleRange: ClosedRange<Double> = 0...180

    var isUsable: Bool {
        openAngle - closedAngle >= 20 && Self.plausibleRange.contains(closedAngle)
            && Self.plausibleRange.contains(openAngle)
    }

    /// How much of the effect responds across the whole travel rather than only
    /// inside the band.
    ///
    /// A hard band puts the whole effect near the stop, which is where it belongs, but
    /// it also means nothing whatsoever happens for the first stretch of movement, and
    /// a lid moved slowly can go for a second or two with the screen inert. That reads
    /// as the app not responding, and it is not obviously distinguishable from a bug.
    ///
    /// So a small share of the effect tracks the full travel. Move the lid anywhere and
    /// something answers immediately; the bulk of it still waits for the band.
    static let fullTravelShare = 0.18

    /// Openness. Mostly across the animation band, partly across the whole travel.
    func progress(for angle: Double, startAngle: Double = defaultStartAngle) -> Double {
        guard isUsable else { return normalize(angle, in: 0...startAngle) }
        let banded = normalize(angle, in: animationRange(startAngle: startAngle))
        let full = normalize(angle, in: closedAngle...openAngle)
        return clamp(
            banded * (1 - Self.fullTravelShare) + full * Self.fullTravelShare, 0, 1
        )
    }

    /// Lowers the closed end toward the lowest angle the sensor has ever reported.
    ///
    /// Only the floor is learned here. The open end moves with the user and is owned by
    /// `OpenReference`; a lid resting shut produces a far more repeatable reading than
    /// whatever angle someone happens to be working at.
    mutating func observe(angle: Double) {
        guard Self.plausibleRange.contains(angle), angle < closedAngle else { return }
        closedAngle = angle
    }
}
