import XCTest
@testable import Bendable

final class LidStateMachineTests: XCTestCase {
    private func state(_ progress: Double, _ direction: HingeDirection = .closing) -> HingeState {
        HingeState(
            angle: progress * 120, progress: progress, velocity: direction == .closing ? -0.5 : 0.5,
            direction: direction, isClosed: progress <= 0.02, timestamp: 0
        )
    }

    func testOverlayEngagesOnceTheLidStartsMoving() {
        var machine = LidStateMachine()
        XCTAssertEqual(machine.handle(state(1.0)).phase, .idle)

        let engaged = machine.handle(state(0.9))
        XCTAssertEqual(engaged.phase, .tracking)
        XCTAssertTrue(engaged.showOverlay)
        XCTAssertTrue(engaged.requestCapture)
        XCTAssertTrue(engaged.render)
    }

    func testFullyReopeningTearsTheOverlayDown() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.6))
        let released = machine.handle(state(1.0, .opening))
        XCTAssertEqual(released.phase, .idle)
        XCTAssertTrue(released.hideOverlay)
        XCTAssertTrue(released.releaseCapture)
    }

    func testInterruptedCloseResumesWithoutRestarting() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.8))
        _ = machine.handle(state(0.4))
        let reversed = machine.handle(state(0.6, .opening))
        XCTAssertEqual(reversed.phase, .tracking)
        XCTAssertFalse(reversed.showOverlay, "The overlay is already up; re-showing would restart it")
        XCTAssertFalse(reversed.requestCapture, "The desktop image must not be refetched mid-gesture")
    }

    func testReachingTheStopMarksNearlyClosed() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        XCTAssertEqual(machine.handle(state(0.0)).phase, .nearlyClosed)
    }

    func testReopeningBeforeSleepPicksStraightBackUp() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        _ = machine.handle(state(0.0))
        let resumed = machine.handle(state(0.3, .opening))
        XCTAssertEqual(resumed.phase, .tracking)
        XCTAssertTrue(resumed.render)
    }

    func testSleepReleasesTheDesktopImage() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        _ = machine.handle(state(0.0))
        let sleeping = machine.handle(PowerEvent.systemWillSleep)
        XCTAssertEqual(sleeping.phase, .sleeping)
        XCTAssertTrue(sleeping.releaseCapture, "The desktop must not survive into a locked session")
    }

    func testSleepPartwayThroughAnAnimationStopsRendering() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.45))
        let transition = machine.handle(PowerEvent.systemWillSleep)
        XCTAssertEqual(transition.phase, .sleeping)
        XCTAssertFalse(transition.render)
    }

    func testWakingReplaysTheOpeningAnimation() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        _ = machine.handle(state(0.0))
        _ = machine.handle(PowerEvent.systemWillSleep)
        XCTAssertEqual(machine.handle(PowerEvent.systemDidWake).phase, .waking)

        let opening = machine.handle(state(0.2, .opening))
        XCTAssertEqual(opening.phase, .tracking)
        XCTAssertTrue(opening.showOverlay)
        XCTAssertTrue(opening.requestCapture, "A fresh still is needed; the pre-sleep one was dropped")
    }

    func testWakingStraightToFullyOpenSkipsTheAnimation() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        _ = machine.handle(PowerEvent.systemWillSleep)
        _ = machine.handle(PowerEvent.systemDidWake)
        XCTAssertEqual(machine.handle(state(1.0, .opening)).phase, .idle)
    }

    func testClamshellIsDistinguishedFromSleep() {
        var machine = LidStateMachine()
        machine.externalDisplayAttached = true
        _ = machine.handle(state(0.5))
        _ = machine.handle(state(0.0))
        let transition = machine.handle(PowerEvent.displaysDidSleep)
        XCTAssertEqual(transition.phase, .clamshell)
        XCTAssertTrue(transition.releaseCapture)
    }

    func testOpeningFromClamshellReengages() {
        var machine = LidStateMachine()
        machine.externalDisplayAttached = true
        _ = machine.handle(state(0.5))
        _ = machine.handle(state(0.0))
        _ = machine.handle(PowerEvent.displaysDidSleep)
        let reopened = machine.handle(state(0.4, .opening))
        XCTAssertEqual(reopened.phase, .tracking)
        XCTAssertTrue(reopened.showOverlay)
    }

    func testLockingReleasesTheDesktopImageWithoutChangingPhase() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        let locked = machine.handle(PowerEvent.screenLocked)
        XCTAssertEqual(locked.phase, .tracking)
        XCTAssertTrue(locked.releaseCapture)
    }

    func testClosingCanBeDisabledIndependently() {
        var machine = LidStateMachine()
        machine.animatesClosing = false
        XCTAssertEqual(machine.handle(state(0.5, .closing)).phase, .idle)

        machine.animatesClosing = true
        machine.animatesOpening = false
        _ = machine.handle(state(0.5, .closing))
        XCTAssertEqual(machine.handle(state(0.7, .opening)).phase, .idle)
    }

    func testDisablingTearsEverythingDown() {
        var machine = LidStateMachine()
        _ = machine.handle(state(0.5))
        let disabled = machine.setEnabled(false)
        XCTAssertEqual(disabled.phase, .idle)
        XCTAssertTrue(disabled.hideOverlay)
        XCTAssertEqual(machine.handle(state(0.3)).phase, .idle)
    }

    func testSensorNoiseAroundFullyOpenDoesNotRaiseTheOverlay() {
        var machine = LidStateMachine()
        for progress in [1.0, 0.999, 0.997, 1.0, 0.998] {
            XCTAssertEqual(machine.handle(state(progress)).phase, .idle)
        }
    }
}
