import XCTest
@testable import Bendable

final class HingeCalibrationTests: XCTestCase {
    func testDefaultCalibrationMapsEndpoints() {
        let calibration = HingeCalibration.default
        XCTAssertEqual(calibration.progress(for: calibration.closedAngle), 0, accuracy: 0.0001)
        XCTAssertEqual(calibration.progress(for: calibration.openAngle), 1, accuracy: 0.0001)
    }

    /// The open end is owned by `OpenReference`, which follows the lid; `observe` only
    /// learns the hardware floor.
    func testObservingDoesNotMoveTheOpenEnd() {
        var calibration = HingeCalibration.default
        calibration.observe(angle: 132)
        XCTAssertEqual(calibration.openAngle, HingeCalibration.default.openAngle, accuracy: 0.001)
    }

    func testClosedEndTracksLowestObservedAngle() {
        var calibration = HingeCalibration(closedAngle: 4, openAngle: 100)
        calibration.observe(angle: 1.5)
        XCTAssertEqual(calibration.closedAngle, 1.5, accuracy: 0.001)
    }

    func testImplausibleObservationsAreIgnored() {
        var calibration = HingeCalibration(closedAngle: 5, openAngle: 100)
        calibration.observe(angle: -12)
        calibration.observe(angle: 511)
        XCTAssertEqual(calibration, HingeCalibration(closedAngle: 5, openAngle: 100))
    }

    func testDegenerateRangeFallsBackToADefaultMapping() {
        let calibration = HingeCalibration(closedAngle: 50, openAngle: 55)
        XCTAssertFalse(calibration.isUsable)
        XCTAssertEqual(calibration.progress(for: 95), 1, accuracy: 0.001)
    }

    func testRoundTripsThroughCodable() throws {
        let calibration = HingeCalibration(closedAngle: 2, openAngle: 118)
        let data = try JSONEncoder().encode(calibration)
        XCTAssertEqual(try JSONDecoder().decode(HingeCalibration.self, from: data), calibration)
    }
}
