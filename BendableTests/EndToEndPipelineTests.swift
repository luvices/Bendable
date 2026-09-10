import XCTest
@testable import Bendable

/// Drives sensor samples all the way to frames, which is the contract that actually
/// matters: nothing in between is allowed to introduce a jump, a flash or a restart.
@MainActor
final class EndToEndPipelineTests: XCTestCase {
    @MainActor
    private struct Rig {
        var normalizer: HingeNormalizer
        var machine: LidStateMachine
        var engine: AnimationEngine
        var time: TimeInterval = 0

        init(preset: any AnimationPreset = FoldPreset(), smoothing: Double = 0.3) {
            normalizer = HingeNormalizer(
                calibration: HingeCalibration(closedAngle: 0, openAngle: 120),
                smoothing: smoothing, autoCalibrates: false
            )
            machine = LidStateMachine()
            engine = AnimationEngine(preset: preset)
        }

        mutating func feed(_ angle: Double, interval: TimeInterval = 1.0 / 120)
            -> (state: HingeState, transition: LidTransition, frame: FrameDescription)? {
            time += interval
            guard let state = normalizer.normalize(
                HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: time)
            ) else { return nil }
            let transition = machine.handle(state)
            return (state, transition, engine.frame(for: state))
        }
    }

    func testFullCloseEndsBlackAndFullOpenEndsClear() {
        var rig = Rig()
        var last: FrameDescription?
        for angle in stride(from: 120.0, through: 0.0, by: -1.0) {
            last = rig.feed(angle)?.frame
        }
        XCTAssertTrue(last?.isOpaqueBlack ?? false)
        XCTAssertEqual(rig.machine.phase, .nearlyClosed)

        for angle in stride(from: 0.0, through: 120.0, by: 1.0) {
            last = rig.feed(angle)?.frame
        }
        // The lid comes to rest: the sensor keeps reporting the same angle and the
        // overlay is torn down once the movement has settled.
        for _ in 0..<40 { last = rig.feed(120)?.frame }
        XCTAssertEqual(rig.machine.phase, .idle)
        XCTAssertEqual(last?.foldAngle ?? 1, 0, accuracy: 0.02)
    }

    func testFoldAngleNeverJumpsBetweenConsecutiveFrames() {
        var rig = Rig()
        var previous: Double?
        var largestStep = 0.0
        for angle in stride(from: 120.0, through: 0.0, by: -0.5) {
            guard let result = rig.feed(angle) else { continue }
            if let previous {
                largestStep = max(largestStep, abs(result.frame.foldAngle - previous))
            }
            previous = result.frame.foldAngle
        }
        // 0.5° of hinge travel must never move the panel more than a couple of degrees.
        XCTAssertLessThan(largestStep, 0.05, "Largest single-frame fold step was \(largestStep) rad")
    }

    func testScrubbingBackAndForthReversesImmediately() {
        var rig = Rig()
        // Down into the band, where the effect actually lives.
        for angle in stride(from: 120.0, through: 20.0, by: -2.0) { _ = rig.feed(angle) }
        let atTurnaround = rig.feed(18)?.frame.blur ?? 0
        XCTAssertGreaterThan(atTurnaround, 0.1, "The effect should be well underway here")

        var reopened = atTurnaround
        for angle in stride(from: 20.0, through: 42.0, by: 2.0) {
            reopened = rig.feed(angle)?.frame.blur ?? reopened
        }
        XCTAssertLessThan(reopened, atTurnaround, "Reopening must reverse, not replay the close")
        XCTAssertEqual(rig.machine.phase, .tracking)
    }

    func testGeometricPresetsReverseTheSameWay() {
        var rig = Rig(preset: CreasePreset())
        for angle in stride(from: 120.0, through: 20.0, by: -2.0) { _ = rig.feed(angle) }
        let atTurnaround = rig.feed(18)?.frame.foldAngle ?? 0
        XCTAssertGreaterThan(atTurnaround, 0.1)

        var reopened = atTurnaround
        for angle in stride(from: 20.0, through: 42.0, by: 2.0) {
            reopened = rig.feed(angle)?.frame.foldAngle ?? reopened
        }
        XCTAssertLessThan(reopened, atTurnaround, "Reopening must unfold, not replay the close")
    }

    func testSleepPartwayThroughThenWakeAndOpen() {
        var rig = Rig()
        // A degree at a time, which is how the sensor actually reports; the fit is
        // entitled to smooth a coarser sweep that jumps to the stop.
        for angle in stride(from: 120.0, through: 0.0, by: -1.0) { _ = rig.feed(angle) }
        XCTAssertEqual(rig.machine.phase, .nearlyClosed)

        XCTAssertEqual(rig.machine.handle(PowerEvent.systemWillSleep).phase, .sleeping)
        // Readings that arrive while asleep must not resurrect the overlay.
        _ = rig.feed(3)
        XCTAssertEqual(rig.machine.phase, .sleeping)

        XCTAssertEqual(rig.machine.handle(PowerEvent.systemDidWake).phase, .waking)
        rig.normalizer.reset()
        let resumed = rig.feed(20)
        XCTAssertEqual(resumed?.transition.phase, .tracking)
        XCTAssertTrue(resumed?.transition.requestCapture ?? false)
    }

    func testProviderFailureLeavesTheAppInAWorkingIdleState() {
        var rig = Rig()
        _ = rig.feed(120)
        // Nothing arrives after this point; the machine must stay idle and quiet.
        for _ in 0..<10 {
            XCTAssertEqual(rig.machine.phase, .idle)
        }
    }

    func testEveryPresetSurvivesAFullSweepWithFiniteOutput() {
        for preset in AnimationPresetCatalog.all {
            var rig = Rig(preset: preset)
            for angle in stride(from: 120.0, through: 0.0, by: -1.0) {
                guard let frame = rig.feed(angle)?.frame else { continue }
                XCTAssertTrue(frame.foldAngle.isFinite)
                XCTAssertTrue(frame.brightness.isFinite)
                XCTAssertTrue((0...1).contains(frame.opacity), "\(preset.id) opacity \(frame.opacity)")
                XCTAssertTrue((0...1).contains(frame.blur), "\(preset.id) blur \(frame.blur)")
            }
        }
    }

    func testDuplicateReadingsDoNotProduceSpuriousMotion() {
        var rig = Rig()
        for _ in 0..<30 { _ = rig.feed(120) }
        let steady = rig.feed(120)
        XCTAssertEqual(steady?.state.direction, .still)
        XCTAssertEqual(rig.machine.phase, .idle)
    }
}
