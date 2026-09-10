import XCTest
@testable import Bendable

@MainActor
final class PreferencesTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.bendable.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultsAreSensibleOnFirstLaunch() throws {
        let preferences = Preferences(defaults: try makeDefaults())
        XCTAssertTrue(preferences.enabled)
        XCTAssertEqual(preferences.presetID, FoldPreset.id)
        XCTAssertTrue(preferences.animatesClosing)
        XCTAssertTrue(preferences.animatesOpening)
        XCTAssertFalse(preferences.hasCompletedFirstRun)
        XCTAssertEqual(preferences.calibration, .default)
        XCTAssertEqual(preferences.smoothing, 0.25, accuracy: 0.0001)
    }

    func testSettingsPersistAcrossInstances() throws {
        let defaults = try makeDefaults()
        let first = Preferences(defaults: defaults)
        first.presetID = ShutterPreset.id
        first.closingIntensity = 0.4
        first.calibration = HingeCalibration(closedAngle: 1, openAngle: 133)

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.presetID, ShutterPreset.id)
        XCTAssertEqual(second.closingIntensity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(second.calibration.openAngle, 133, accuracy: 0.0001)
    }

    func testResettingCalibrationRestoresTheDefault() throws {
        let defaults = try makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.calibration = HingeCalibration(closedAngle: 3, openAngle: 140)
        preferences.resetCalibration()
        XCTAssertEqual(preferences.calibration, .default)
        XCTAssertEqual(Preferences(defaults: defaults).calibration, .default)
    }
}
