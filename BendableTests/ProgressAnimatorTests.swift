import XCTest
@testable import Bendable

/// The sensor reports whole degrees, and only when they change, so readings arrive
/// several display refreshes apart. These are the properties that turn that into
/// continuous motion without ever getting ahead of the lid.
final class ProgressAnimatorTests: XCTestCase {
    private let refresh = 1.0 / 60

    func testItStartsWhereItIsPut() {
        var animator = ProgressAnimator(value: 0.4)
        XCTAssertEqual(animator.value, 0.4, accuracy: 0.0001)
        animator.reset(to: 0.9)
        XCTAssertEqual(animator.value, 0.9, accuracy: 0.0001)
    }

    /// The property everything else is built on. An earlier version predicted ahead
    /// using the measured rate, which meant letting go of the lid left the animation
    /// still running: a prediction has no way to know the movement has stopped.
    func testItNeverPassesTheReading() {
        var animator = ProgressAnimator(value: 1)
        for _ in 0..<200 {
            animator.advance(target: 0.4, dt: refresh, reportInterval: 0.3)
            XCTAssertGreaterThanOrEqual(animator.value, 0.4 - 0.0001, "It went past")
        }

        animator.reset(to: 0)
        for _ in 0..<200 {
            animator.advance(target: 0.6, dt: refresh, reportInterval: 0.3)
            XCTAssertLessThanOrEqual(animator.value, 0.6 + 0.0001, "It went past")
        }
    }

    /// A lid let go of mid-movement must stop with it, however briskly it had been
    /// moving and however long the sensor then stays quiet.
    func testAStoppedLidStops() {
        var animator = ProgressAnimator(value: 1)
        for _ in 0..<40 { animator.advance(target: 0.5, dt: refresh, reportInterval: 0.02) }
        let settled = animator.value
        XCTAssertEqual(settled, 0.5, accuracy: 0.01)

        // Two seconds of silence, exactly as the sensor gives when nothing moves.
        for _ in 0..<120 { animator.advance(target: 0.5, dt: refresh, reportInterval: 0.4) }
        XCTAssertEqual(animator.value, 0.5, accuracy: 0.001, "It drifted after the lid stopped")
    }

    /// A quantised step must be spread across frames, not passed straight through.
    func testAReadingIsSpreadAcrossFrames() {
        var animator = ProgressAnimator(value: 0.5)
        var deltas: [Double] = []
        var previous = animator.value
        for _ in 0..<10 {
            animator.advance(target: 0.48, dt: refresh, reportInterval: 0.09)
            deltas.append(abs(animator.value - previous))
            previous = animator.value
        }
        XCTAssertLessThan(deltas.max() ?? 1, 0.009, "The step went straight through")
        XCTAssertEqual(animator.value, 0.48, accuracy: 0.004, "but it still has to arrive")
    }

    /// Lag is the time constant times the rate, and one reading is one degree, so
    /// easing over half an interval leaves it about half a degree behind at any speed.
    func testLagIsAboutHalfADegreeWhateverTheSpeed() {
        for (interval, rate) in [(0.02, 2.0), (0.09, 0.44), (0.2, 0.2)] {
            var animator = ProgressAnimator(value: 1)
            var truth = 1.0
            // Readings land on their own cadence; frames run at the display's.
            var sinceReading = 0.0
            var reported = truth
            // Stopped well short of the end, since the animator clamps to 0...1 and a
            // comparison against a truth that has left the range is meaningless.
            while truth > 0.3 {
                truth -= rate * refresh
                sinceReading += refresh
                if sinceReading >= interval {
                    reported = truth
                    sinceReading = 0
                }
                animator.advance(target: reported, dt: refresh, reportInterval: interval)
            }
            let lag = animator.value - truth
            // One reading is one degree, so the quantum is the natural unit to judge
            // the lag in. Half of it comes from the easing and the rest from the
            // reading in hand already being up to a quantum old.
            let quantum = interval * rate
            XCTAssertGreaterThan(lag, -0.0001, "It should be behind, never ahead")
            XCTAssertLessThan(
                lag, quantum * 3, "Lag is out of proportion to the cadence: \(lag) vs \(quantum)"
            )
        }
    }

    func testEasingIsStretchedToTheSensorsCadence() {
        XCTAssertGreaterThan(
            ProgressAnimator.easeTime(forReportInterval: 0.2),
            ProgressAnimator.easeTime(forReportInterval: 0.01)
        )
        XCTAssertEqual(
            ProgressAnimator.easeTime(forReportInterval: 0),
            ProgressAnimator.minimumEase, accuracy: 0.0001
        )
        XCTAssertEqual(
            ProgressAnimator.easeTime(forReportInterval: 10),
            ProgressAnimator.maximumEase, accuracy: 0.0001
        )
    }

    func testReversingDirectionIsFollowedPromptly() {
        var animator = ProgressAnimator(value: 1)
        for _ in 0..<30 { animator.advance(target: 0.5, dt: refresh, reportInterval: 0.03) }
        let atTurnaround = animator.value
        for _ in 0..<6 { animator.advance(target: 0.62, dt: refresh, reportInterval: 0.03) }
        XCTAssertGreaterThan(animator.value, atTurnaround)
    }

    func testItNeverLeavesTheUnitRange() {
        var animator = ProgressAnimator(value: 0.05)
        for _ in 0..<60 { animator.advance(target: 0, dt: refresh, reportInterval: 0.02) }
        XCTAssertEqual(animator.value, 0, accuracy: 0.0001)

        for _ in 0..<60 { animator.advance(target: 1, dt: refresh, reportInterval: 0.02) }
        XCTAssertEqual(animator.value, 1, accuracy: 0.0001)
    }

    /// A stalled main thread must not be swept through in one enormous sweep.
    func testAStallSnapsRatherThanSweeps() {
        var animator = ProgressAnimator(value: 1)
        animator.advance(target: 0.2, dt: 3, reportInterval: 0.02)
        XCTAssertEqual(animator.value, 0.2, accuracy: 0.0001)
    }

    func testMonotonicMovementStaysMonotonic() {
        var animator = ProgressAnimator(value: 1)
        var previous = 1.0
        var truth = 1.0
        for step in 0..<180 {
            truth = max(truth - 0.005, 0)
            let reported = step % 3 == 0 ? truth : previous
            animator.advance(target: reported, dt: refresh, reportInterval: 3 * refresh)
            XCTAssertLessThanOrEqual(animator.value, previous + 0.0005, "went backwards at \(step)")
            previous = animator.value
        }
    }

    func testSettlingIsReportedOnceItHasCaughtUp() {
        var animator = ProgressAnimator(value: 1)
        XCTAssertFalse(animator.hasSettled(at: 0.3))
        for _ in 0..<80 { animator.advance(target: 0.3, dt: refresh, reportInterval: 0.02) }
        XCTAssertTrue(animator.hasSettled(at: 0.3))
    }
}
