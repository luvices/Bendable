import XCTest
@testable import Bendable

final class HingeNormalizerTests: XCTestCase {
    /// Monotonic across sweeps within one test, so a second sweep continues the first
    /// rather than replaying timestamps the filter has already seen.
    private var clock: TimeInterval = 0

    override func setUp() {
        super.setUp()
        clock = 0
    }

    /// Feeds a sweep at a fixed cadence and returns the resulting states.
    private func sweep(
        _ angles: [Double], normalizer: inout HingeNormalizer, interval: TimeInterval = 1.0 / 120
    ) -> [HingeState] {
        angles.compactMap { angle in
            clock += interval
            return normalizer.normalize(HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: clock))
        }
    }

    func testProgressSpansTheCalibratedRange() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0, autoCalibrates: false
        )
        let states = sweep(Array(stride(from: 0.0, through: 120.0, by: 1.0)), normalizer: &normalizer)

        XCTAssertEqual(states.first?.progress ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(states.last?.progress ?? 0, 1, accuracy: 0.02)
    }

    func testMonotonicOpeningSweepIsMonotonicInProgress() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.3, autoCalibrates: false
        )
        let states = sweep([0, 30, 60, 90, 120], normalizer: &normalizer, interval: 0.05)
        let progresses = states.map(\.progress)
        XCTAssertEqual(progresses, progresses.sorted())
    }

    func testClosingSweepReportsClosingDirection() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.2, autoCalibrates: false
        )
        let states = sweep([120, 90, 60, 30, 0], normalizer: &normalizer, interval: 0.05)
        XCTAssertEqual(states.last?.direction, .closing)
        XCTAssertLessThan(states.last?.velocity ?? 0, 0)
        XCTAssertTrue(states.last?.isClosed ?? false)
    }

    func testReversalFlipsDirectionWithoutRestarting() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.2, autoCalibrates: false
        )
        // Inside the animation band, where progress actually moves.
        let closing = sweep([40, 32, 24, 16], normalizer: &normalizer, interval: 0.05)
        XCTAssertEqual(closing.last?.direction, .closing)
        XCTAssertLessThan(closing.last?.progress ?? 1, 0.6)

        let reopening = sweep(
            stride(from: 20.0, through: 44.0, by: 2.0).map { $0 }, normalizer: &normalizer, interval: 0.05
        )
        XCTAssertEqual(reopening.last?.direction, .opening)
        // Progress must continue from where the close stopped, not snap back.
        XCTAssertGreaterThan(reopening.first?.progress ?? 0, closing.last?.progress ?? 1)
    }

    func testJitterIsSuppressedWhileParked() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.8, autoCalibrates: false
        )
        let noisy = (0..<200).map { index -> Double in
            90 + (index % 2 == 0 ? 0.6 : -0.6)
        }
        let states = sweep(noisy, normalizer: &normalizer)
        let tail = states.suffix(60).map(\.progress)
        let spread = (tail.max() ?? 0) - (tail.min() ?? 0)
        XCTAssertLessThan(spread, 0.004, "Sensor dither should not reach the animation")
        XCTAssertEqual(states.last?.direction, .still)
    }

    func testFastMovementIsNotOverSmoothed() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0.8, autoCalibrates: false
        )
        // 120° to 0° in 200 ms is about as fast as a lid can physically be shut.
        let angles = stride(from: 120.0, through: 0.0, by: -5.0).map { $0 }
        let states = sweep(angles, normalizer: &normalizer, interval: 200.0 / 1000 / 24)
        let final = states.last?.angle ?? 999
        XCTAssertLessThan(final, 20, "Adaptive cutoff should keep up with a fast close, lag was \(final)°")
    }

    func testImplausibleReadingsAreRejected() {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: 120), smoothing: 0, autoCalibrates: false
        )
        _ = normalizer.normalize(HingeSample(angle: 90, lidIsOpen: true, timestamp: 1))
        let bad = normalizer.normalize(HingeSample(angle: 511, lidIsOpen: true, timestamp: 2))
        XCTAssertEqual(bad?.angle ?? 0, 90, accuracy: 0.5)

        let nan = normalizer.normalize(HingeSample(angle: .nan, lidIsOpen: true, timestamp: 3))
        XCTAssertEqual(nan?.angle ?? 0, 90, accuracy: 0.5)
    }

    func testDuplicateTimestampsDoNotDivideByZero() {
        var normalizer = HingeNormalizer(smoothing: 0.4, autoCalibrates: false)
        _ = normalizer.normalize(HingeSample(angle: 90, lidIsOpen: true, timestamp: 5))
        let repeated = normalizer.normalize(HingeSample(angle: 91, lidIsOpen: true, timestamp: 5))
        XCTAssertNotNil(repeated)
        XCTAssertTrue(repeated?.velocity.isFinite ?? false)
    }

    func testLidStateOnlySamplesProduceEndpoints() {
        var normalizer = HingeNormalizer(autoCalibrates: false)
        let closed = normalizer.normalize(HingeSample(angle: nil, lidIsOpen: false, timestamp: 1))
        XCTAssertEqual(closed?.progress, 0)
        XCTAssertTrue(closed?.isClosed ?? false)
        XCTAssertNil(closed?.angle)

        let opened = normalizer.normalize(HingeSample(angle: nil, lidIsOpen: true, timestamp: 2))
        XCTAssertEqual(opened?.progress, 1)
        XCTAssertEqual(opened?.direction, .opening)
    }
}
