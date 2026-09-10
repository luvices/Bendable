import XCTest
@testable import Bendable

/// The filter's job here is narrow: hold the angle steady while the lid is parked and
/// dithering across a degree boundary, and get out of the way the moment it moves. The
/// speed that decides which is happening is measured elsewhere, by `AngularFit`. The
/// filter's own derivative could never tell dither from movement on a signal quantised
/// to whole degrees.
final class OneEuroFilterTests: XCTestCase {
    private let interval = 1.0 / 125

    func testFirstSampleIsPassedThroughUnchanged() {
        var filter = OneEuroFilter()
        XCTAssertEqual(filter.apply(42, at: 1, speed: 0), 42)
    }

    func testSteadySignalConverges() {
        var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
        var time = 0.0
        var value = 0.0
        for _ in 0..<200 {
            time += interval
            value = filter.apply(90, at: time, speed: 0)
        }
        XCTAssertEqual(value, 90, accuracy: 0.01)
    }

    /// A parked lid crossing a degree boundary must not reach the screen.
    func testDitherIsSuppressedWhileParked() {
        var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
        var time = 0.0
        var outputs: [Double] = []
        for index in 0..<400 {
            time += interval
            outputs.append(filter.apply(90 + (index % 2 == 0 ? 1 : -1), at: time, speed: 0))
        }
        let tail = outputs.suffix(100)
        let spread = (tail.max() ?? 0) - (tail.min() ?? 0)
        XCTAssertLessThan(spread, 0.35, "A degree of dither is reaching the screen")
    }

    /// And the moment the lid is actually moving, the filter has to be transparent.
    func testMovementPassesStraightThrough() {
        var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
        var time = 0.0
        var value = 90.0
        var truth = 90.0
        for _ in 0..<200 {
            time += interval
            truth -= 40 * interval
            value = filter.apply(truth, at: time, speed: -40)
        }
        XCTAssertEqual(value, truth, accuracy: 0.35, "The filter is in the way of real movement")
    }

    func testFasterMovementIsFilteredLess() {
        func trail(atSpeed speed: Double, rate: Double) -> Double {
            var filter = OneEuroFilter(minCutoff: 3.2, beta: 2.0)
            var time = 0.0
            var truth = 90.0
            var value = 90.0
            for _ in 0..<200 {
                time += interval
                truth -= rate * interval
                value = filter.apply(truth, at: time, speed: speed)
            }
            return value - truth
        }
        XCTAssertLessThan(trail(atSpeed: -60, rate: 60), trail(atSpeed: -6, rate: 6) * 6)
    }

    func testNonIncreasingTimestampsAreIgnored() {
        var filter = OneEuroFilter()
        _ = filter.apply(10, at: 5, speed: 0)
        XCTAssertEqual(filter.apply(90, at: 5, speed: 0), 10)
        XCTAssertEqual(filter.apply(90, at: 4, speed: 0), 10)
    }

    func testResetClearsHistory() {
        var filter = OneEuroFilter()
        _ = filter.apply(10, at: 1, speed: 0)
        filter.reset()
        XCTAssertEqual(filter.apply(90, at: 2, speed: 0), 90)
    }
}
