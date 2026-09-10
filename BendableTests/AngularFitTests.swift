import XCTest
@testable import Bendable

/// The sensor reports whole degrees. Everything here is about getting a usable
/// position and rate out of a signal that coarse.
final class AngularFitTests: XCTestCase {
    /// Feeds a constant-rate movement, quantised the way the hardware quantises it.
    private func sweep(
        _ fit: inout AngularFit, from start: Double, rate: Double, duration: TimeInterval,
        interval: TimeInterval = 1.0 / 125, dither: Double = 0
    ) -> [AngularFit.Estimate] {
        var estimates: [AngularFit.Estimate] = []
        var time = 0.0
        var lastReported: Double?
        var step = 0
        while time < duration {
            time += interval
            step += 1
            let truth = start + rate * time
            let reported = (truth + sin(Double(step) * 1.7) * dither).rounded()
            // The sensor only speaks when the whole degree changes.
            guard reported != lastReported else { continue }
            lastReported = reported
            estimates.append(fit.update(angle: reported, at: time))
        }
        return estimates
    }

    func testItRecoversAConstantRateThroughQuantisation() {
        var fit = AngularFit()
        let estimates = sweep(&fit, from: 90, rate: -12, duration: 2)
        let settled = estimates.suffix(20).map(\.degreesPerSecond)
        for rate in settled {
            XCTAssertEqual(rate, -12, accuracy: 1.5)
        }
    }

    func testItRecoversASlowRateWhereDifferencingWouldNot() {
        var fit = AngularFit()
        // Three degrees a second: a reading only every third of a second.
        let estimates = sweep(&fit, from: 60, rate: -3, duration: 6)
        let settled = estimates.suffix(8).map(\.degreesPerSecond)
        for rate in settled {
            XCTAssertEqual(rate, -3, accuracy: 1.0)
        }
    }

    /// Dither across a degree boundary must not send the rate backwards.
    func testDitherDoesNotReverseTheRate() {
        var fit = AngularFit()
        let estimates = sweep(&fit, from: 70, rate: -8, duration: 4, dither: 0.4)
        let settled = estimates.suffix(30).map(\.degreesPerSecond)
        for rate in settled {
            XCTAssertLessThan(rate, 0, "The rate flipped sign on dither")
            XCTAssertEqual(rate, -8, accuracy: 3)
        }
    }

    /// The fitted position must track the true angle, not trail it the way a low-pass
    /// would, which is the whole reason for fitting rather than filtering.
    func testTheFittedAngleDoesNotTrailSteadyMovement() {
        var fit = AngularFit()
        let rate = -10.0
        var time = 0.0
        var lastReported: Double?
        var worstTrail = 0.0
        while time < 3 {
            time += 1.0 / 125
            let truth = 90 + rate * time
            let reported = truth.rounded()
            guard reported != lastReported else { continue }
            lastReported = reported
            let estimate = fit.update(angle: reported, at: time)
            if time > 0.6 {
                worstTrail = max(worstTrail, estimate.angle - truth)
            }
        }
        XCTAssertLessThan(worstTrail, 0.8, "The fitted angle is behind the lid")
    }

    func testAStationaryLidReportsNoMovement() {
        var fit = AngularFit()
        var time = 0.0
        var estimate = AngularFit.Estimate(angle: 0, degreesPerSecond: 0)
        // The heartbeat: the same angle, once a second.
        for _ in 0..<8 {
            time += 1.0
            estimate = fit.update(angle: 95, at: time)
        }
        XCTAssertEqual(estimate.degreesPerSecond, 0, accuracy: 0.2)
        XCTAssertEqual(estimate.angle, 95, accuracy: 0.2)
    }

    func testAReversalIsFollowed() {
        var fit = AngularFit()
        _ = sweep(&fit, from: 90, rate: -20, duration: 1)
        var time = 1.0
        var estimate = AngularFit.Estimate(angle: 0, degreesPerSecond: 0)
        var lastReported: Double?
        while time < 1.6 {
            time += 1.0 / 125
            let reported = (70 + 20 * (time - 1)).rounded()
            guard reported != lastReported else { continue }
            lastReported = reported
            estimate = fit.update(angle: reported, at: time)
        }
        XCTAssertGreaterThan(estimate.degreesPerSecond, 0, "It is still closing")
    }

    func testOutOfOrderAndDuplicateReadingsAreIgnored() {
        var fit = AngularFit()
        _ = fit.update(angle: 90, at: 1)
        _ = fit.update(angle: 88, at: 1.1)
        let good = fit.update(angle: 86, at: 1.2)
        let repeated = fit.update(angle: 40, at: 1.2)
        XCTAssertEqual(repeated.angle, good.angle, accuracy: 0.0001)
        let backwards = fit.update(angle: 40, at: 0.5)
        XCTAssertEqual(backwards.angle, good.angle, accuracy: 0.0001)
    }

    /// After sleep the lid may have moved unobserved, so the fit must start again
    /// rather than drawing a line across the gap.
    func testALongGapRestartsTheFit() {
        var fit = AngularFit()
        _ = sweep(&fit, from: 90, rate: -30, duration: 1)
        let afterGap = fit.update(angle: 20, at: 600)
        XCTAssertEqual(afterGap.degreesPerSecond, 0, accuracy: 0.0001)
        XCTAssertEqual(afterGap.angle, 20, accuracy: 0.0001)
    }
}
