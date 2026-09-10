import XCTest
@testable import Bendable

final class OpenReferenceTests: XCTestCase {
    private let step = 1.0 / 60

    /// Feeds a parked lid at `angle` for `duration`, and returns where the reference ends up.
    private func park(
        _ reference: inout OpenReference, at angle: Double, for duration: TimeInterval,
        closedAngle: Double = 0
    ) {
        var elapsed = 0.0
        while elapsed < duration {
            reference.update(angle: angle, degreesPerSecond: 0, dt: step, closedAngle: closedAngle)
            elapsed += step
        }
    }

    func testOpeningWiderIsAdoptedQuickly() {
        var reference = OpenReference(angle: 95)
        park(&reference, at: 125, for: 3)
        XCTAssertEqual(reference.angle, 125, accuracy: 1)
    }

    /// The user's own working angle has to become 1.0, or the last stretch of travel
    /// does nothing and the effect is already partly applied while they work.
    func testASmallerWorkingAngleIsEventuallyAdopted() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 5)
        XCTAssertEqual(reference.angle, 130, accuracy: 0.5, "Five seconds is not a new posture")

        park(&reference, at: 100, for: 20)
        XCTAssertEqual(reference.angle, 100, accuracy: 1.5)
    }

    func testPausingPartWayThroughClosingDoesNotCancelTheAnimation() {
        var reference = OpenReference(angle: 100)
        // A two second pause on the way down is a hesitation, not a new resting place.
        park(&reference, at: 45, for: 2)
        XCTAssertEqual(reference.angle, 100, accuracy: 0.5)
    }

    func testMovementSuspendsLearningEntirely() {
        var reference = OpenReference(angle: 95)
        var elapsed = 0.0
        while elapsed < 5 {
            reference.update(angle: 130, degreesPerSecond: 20, dt: step, closedAngle: 0)
            elapsed += step
        }
        XCTAssertEqual(reference.angle, 95, accuracy: 0.0001)
    }

    func testAShutLidNeverBecomesTheDefinitionOfOpen() {
        var reference = OpenReference(angle: 100)
        // Exactly what a closed lid or a clamshell session looks like: parked at zero
        // for a long time.
        park(&reference, at: 0, for: 60)
        XCTAssertEqual(reference.angle, 100, accuracy: 0.0001)
    }

    func testAGapInSamplesRestartsTheDwell() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 5.5)
        // A sleep/wake cycle: the lid could have moved unobserved.
        reference.update(angle: 100, degreesPerSecond: 0, dt: 40, closedAngle: 0)
        park(&reference, at: 100, for: 1)
        XCTAssertEqual(reference.angle, 130, accuracy: 0.5, "The dwell should have restarted")
    }

    func testResetClearsBothAngleAndDwell() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 5.5)
        reference.reset(to: 110)
        XCTAssertEqual(reference.angle, 110, accuracy: 0.0001)
        park(&reference, at: 100, for: 1)
        XCTAssertEqual(reference.angle, 110, accuracy: 0.5)
    }
}

final class DynamicOpenAngleTests: XCTestCase {
    /// End to end: a lid that has once been pushed right back must still reach a full
    /// 1.0 at whatever angle its owner actually works at.
    func testWorkingAngleReachesFullyOpen() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 135),
            smoothing: 0.25, autoCalibrates: true
        )

        var time = 0.0
        var state: HingeState?
        // Sit at a normal working angle for half a minute.
        while time < 30 {
            time += 1.0 / 60
            state = normalizer.normalize(
                HingeSample(angle: 100, lidIsOpen: true, timestamp: time)
            )
        }

        XCTAssertEqual(state?.progress ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(normalizer.calibration.openAngle, 100, accuracy: 2)
    }

    /// The effect runs in a band above closed, so the top of the travel is
    /// deliberately inert. The band itself still has to be used end to end.
    func testClosingUsesTheWholeBand() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 135),
            smoothing: 0.25, autoCalibrates: true
        )

        var time = 0.0
        while time < 30 {
            time += 1.0 / 60
            _ = normalizer.normalize(HingeSample(angle: 100, lidIsOpen: true, timestamp: time))
        }

        let band = normalizer.animationRange
        XCTAssertEqual(band.upperBound, HingeCalibration.defaultStartAngle, accuracy: 2)

        // Now close it.
        var byAngle: [(angle: Double, progress: Double)] = []
        for angle in stride(from: 100.0, through: 0.0, by: -1.0) {
            time += 1.0 / 60
            if let state = normalizer.normalize(
                HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: time)
            ) {
                byAngle.append((angle, state.progress))
            }
        }

        XCTAssertEqual(byAngle.first?.progress ?? 0, 1, accuracy: 0.01, "Starts fully open")
        XCTAssertLessThan(byAngle.last?.progress ?? 1, 0.03, "and finishes fully closed")

        // Very little above the band, but never nothing.
        for sample in byAngle where sample.angle > band.upperBound + 4 {
            XCTAssertGreaterThan(sample.progress, 0.85, "moved too much at \(sample.angle)°")
        }

        // Halfway down the band is roughly halfway through the effect.
        let midBand = band.upperBound / 2
        let midway = byAngle.min { abs($0.angle - midBand) < abs($1.angle - midBand) }
        XCTAssertEqual(midway?.progress ?? 0, 0.5, accuracy: 0.16, "The band is not mapped evenly")
    }
}

/// The sensor streams at 125 Hz only while the angle is changing; a parked lid emits
/// about one report a second. Every other test here feeds 60 Hz, which is the one rate
/// the hardware never uses when still, and stillness is when this code has work to do.
final class OpenReferenceIdleCadenceTests: XCTestCase {
    private func park(
        _ reference: inout OpenReference, at angle: Double, for duration: TimeInterval,
        interval: TimeInterval
    ) {
        var elapsed = 0.0
        while elapsed < duration {
            reference.update(angle: angle, degreesPerSecond: 0, dt: interval, closedAngle: 0)
            elapsed += interval
        }
    }

    func testTheReferenceLearnsAtTheSensorsIdleReportRate() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 30, interval: 1.0)
        XCTAssertEqual(reference.angle, 100, accuracy: 2, "A heartbeat-rate lid taught it nothing")
    }

    func testOpeningWiderIsAdoptedAtTheIdleRateToo() {
        var reference = OpenReference(angle: 95)
        park(&reference, at: 125, for: 6, interval: 1.0)
        XCTAssertEqual(reference.angle, 125, accuracy: 2)
    }

    /// Whatever the cadence, the outcome should be about the same.
    func testTheOutcomeDoesNotDependOnTheReportRate() {
        for interval in [1.0 / 125, 1.0 / 60, 0.25, 1.0, 2.0] {
            var reference = OpenReference(angle: 130)
            park(&reference, at: 100, for: 30, interval: interval)
            XCTAssertEqual(reference.angle, 100, accuracy: 3, "at \(interval)s intervals")
        }
    }

    func testARealSleepGapStillRestartsTheDwell() {
        var reference = OpenReference(angle: 130)
        park(&reference, at: 100, for: 5, interval: 1.0)
        reference.update(angle: 100, degreesPerSecond: 0, dt: 600, closedAngle: 0)
        park(&reference, at: 100, for: 2, interval: 1.0)
        XCTAssertEqual(reference.angle, 130, accuracy: 1)
    }
}
