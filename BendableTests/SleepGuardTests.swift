import XCTest
@testable import Bendable

/// The setting `SleepGuard` changes is global, outlives the app and needs a password
/// in both directions. None of that can be exercised in a test, but the reasoning
/// about what the switch should say can be, and that is where the mistakes are.
final class SleepGuardStatusTests: XCTestCase {
    func testItReportsTheFourWaysIntentAndRealityCanLineUp() {
        XCTAssertEqual(SleepGuardStatus.resolve(intent: false, actual: false), .off)
        XCTAssertEqual(SleepGuardStatus.resolve(intent: true, actual: true), .on)
        XCTAssertEqual(SleepGuardStatus.resolve(intent: true, actual: false), .revokedElsewhere)
        XCTAssertEqual(SleepGuardStatus.resolve(intent: false, actual: true), .onFromElsewhere)
    }

    /// The switch follows the machine, not the preference.
    ///
    /// A previous run that was killed leaves the setting on with nothing recording that
    /// Bendable asked for it. Showing that switch as off would offer to turn on
    /// something already on, and leave no way to clear it.
    func testTheSwitchFollowsWhatTheMacIsActuallyDoing() {
        XCTAssertTrue(SleepGuardStatus.onFromElsewhere.isActive)
        XCTAssertTrue(SleepGuardStatus.on.isActive)
        XCTAssertFalse(SleepGuardStatus.revokedElsewhere.isActive)
        XCTAssertFalse(SleepGuardStatus.off.isActive)
    }

    /// Reading the setting must never need privileges, or the interface could not show
    /// the truth on a machine where it has no way to change it.
    func testTheSystemStateIsReadableWithoutAuthorization() {
        // Whatever it returns is fine. That it returns at all is the assertion.
        _ = SleepGuard.isSleepDisabled
    }
}
