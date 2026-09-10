import XCTest
@testable import Bendable

/// The animation lives in a band just above closed, not across the whole travel from
/// wherever the lid happens to rest.
final class AnimationBandTests: XCTestCase {
    private let calibration = HingeCalibration(closedAngle: 0, openAngle: 105)

    private func progress(at angle: Double, startAngle: Double = 45) -> Double {
        calibration.progress(for: angle, startAngle: startAngle)
    }

    func testTheEndsAreExact() {
        XCTAssertEqual(progress(at: 105), 1, accuracy: 0.001)
        XCTAssertEqual(progress(at: 0), 0, accuracy: 0.001)
    }

    /// Most of the effect belongs near the stop, so ordinary adjustments of the screen
    /// must leave the picture very nearly alone.
    func testOrdinaryLidAdjustmentsBarelyMoveIt() {
        for angle in stride(from: 105.0, through: 60.0, by: -5.0) {
            XCTAssertGreaterThan(progress(at: angle), 0.87, "\(angle)° moved too much")
        }
    }

    /// But *something* has to answer, or a lid moved slowly sits inert for a second or
    /// more and the app looks broken.
    func testEveryMovementProducesSomeResponse() {
        var previous = progress(at: 105)
        for angle in stride(from: 104.0, through: 60.0, by: -1.0) {
            let current = progress(at: angle)
            XCTAssertLessThan(current, previous, "nothing happened at \(angle)°")
            previous = current
        }
    }

    func testTheBulkOfTheEffectIsInsideTheBand() {
        // Down to the top of the band costs less than a fifth of the effect...
        XCTAssertGreaterThan(progress(at: 45), 0.8)
        // ...and the rest of it happens in the band.
        XCTAssertLessThan(progress(at: 22.5), 0.55)
        XCTAssertLessThan(progress(at: 8), 0.2)
    }

    func testTheBandRespectsTheClosedFloor() {
        let raised = HingeCalibration(closedAngle: 6, openAngle: 100)
        XCTAssertEqual(raised.animationRange(startAngle: 45).lowerBound, 6, accuracy: 0.001)
        XCTAssertEqual(raised.animationRange(startAngle: 45).upperBound, 51, accuracy: 0.001)
        XCTAssertEqual(raised.progress(for: 6, startAngle: 45), 0, accuracy: 0.001)
    }

    /// Somebody who works with the lid barely open must not find the effect already
    /// well underway while they are using the machine.
    func testAShallowRestingAngleNarrowsTheBandRatherThanSwallowingIt() {
        let shallow = HingeCalibration(closedAngle: 0, openAngle: 50)
        XCTAssertEqual(shallow.animationRange(startAngle: 45).upperBound, 37.5, accuracy: 0.001)
        XCTAssertEqual(shallow.progress(for: 50, startAngle: 45), 1, accuracy: 0.001)
        XCTAssertGreaterThan(shallow.progress(for: 45, startAngle: 45), 0.95)
    }

    func testAWiderStartAngleStartsTheEffectSooner() {
        XCTAssertEqual(calibration.animationRange(startAngle: 30).upperBound, 30, accuracy: 0.001)
        XCTAssertEqual(calibration.animationRange(startAngle: 80).upperBound, 78.75, accuracy: 0.001)
        // At fifty degrees a narrow band has barely begun; a wide one is well into it.
        XCTAssertGreaterThan(progress(at: 50, startAngle: 30), 0.85)
        XCTAssertLessThan(progress(at: 50, startAngle: 80), 0.7)
    }
}

@MainActor
final class BandedPipelineTests: XCTestCase {
    private func settled(startAngle: Double, restingAngle: Double) -> HingeNormalizer {
        var normalizer = HingeNormalizer(
            calibration: HingeCalibration(closedAngle: 0, openAngle: restingAngle),
            smoothing: 0.25, autoCalibrates: false
        )
        normalizer.animationStartAngle = startAngle
        return normalizer
    }

    func testMovingTheLidAboveTheBandBarelyMovesTheEffect() {
        var normalizer = settled(startAngle: 45, restingAngle: 105)
        var time = 0.0
        var last: HingeState?
        for angle in stride(from: 105.0, through: 70.0, by: -1.0) {
            time += 1.0 / 60
            last = normalizer.normalize(HingeSample(angle: angle, lidIsOpen: true, timestamp: time))
        }

        // A third of the travel has gone by and only a little of the effect with it.
        XCTAssertGreaterThan(last?.progress ?? 0, 0.88)
        XCTAssertLessThan(last?.progress ?? 1, 1, "Something has to answer the movement")
        XCTAssertLessThan(last?.velocity ?? 0, -0.01)
        XCTAssertEqual(last?.direction, .closing)
    }

    func testTheEffectRunsEndToEndOnceInsideTheBand() {
        var normalizer = settled(startAngle: 45, restingAngle: 105)
        var time = 0.0
        var progresses: [Double] = []
        for angle in stride(from: 105.0, through: 0.0, by: -1.5) {
            time += 1.0 / 60
            if let state = normalizer.normalize(
                HingeSample(angle: angle, lidIsOpen: angle > 1, timestamp: time)
            ) {
                progresses.append(state.progress)
            }
        }
        XCTAssertEqual(progresses.first ?? 0, 1, accuracy: 0.001)
        XCTAssertLessThan(progresses.last ?? 1, 0.03)
        XCTAssertEqual(progresses, progresses.sorted(by: >), "Progress must fall monotonically")
    }
}

final class FoldSweepTests: XCTestCase {
    private func tilt(travel: Double, progress: Double) -> Double {
        var context = AnimationContext()
        context.hingeTravelDegrees = travel
        return FoldPreset()
            .frame(progress: progress, velocity: 0, direction: .closing, context: context)
            .foldAngle * 180 / .pi
    }

    /// A narrow band still has to produce a fold worth looking at.
    func testANarrowBandStillTurnsThePanelProperly() {
        XCTAssertGreaterThan(tilt(travel: 45, progress: 0), 60)
        XCTAssertGreaterThan(tilt(travel: 30, progress: 0), 60)
    }

    /// A band wide enough to need no help is left alone: degree for degree.
    func testAWideBandTurnsDegreeForDegree() {
        XCTAssertEqual(tilt(travel: 100, progress: 0.7), 30, accuracy: 0.5)
        XCTAssertEqual(tilt(travel: 90, progress: 0.5), 45, accuracy: 0.5)
    }

    /// Whatever the band, the mapping must be a straight line in the angle. That is
    /// what makes the picture feel attached, rather than the constant of
    /// proportionality being exactly one.
    func testTheMappingIsLinearInTheAngleForEveryBand() {
        for travel in [25.0, 45.0, 75.0, 110.0] {
            let quarter = tilt(travel: travel, progress: 0.75)
            let half = tilt(travel: travel, progress: 0.5)
            XCTAssertEqual(half, quarter * 2, accuracy: 0.5, "band \(travel)° is not linear")
        }
    }
}

/// A lid is shut in well under a second, so the panel turns a long way between
/// refreshes. Blur that scales with speed is what stops that reading as stepping.
final class MotionBlurTests: XCTestCase {
    private func blur(atSpeed velocity: Double) -> Double {
        FoldPreset()
            .frame(progress: 0.7, velocity: velocity, direction: .closing, context: AnimationContext())
            .blur
    }

    func testSlowMovementStaysSharp() {
        XCTAssertLessThan(blur(atSpeed: -0.1), 0.05)
    }

    func testFastMovementIsVisiblySoftened() {
        XCTAssertGreaterThan(blur(atSpeed: -1.4), 0.2)
    }

    func testBlurRisesWithSpeed() {
        let speeds = [0.0, -0.3, -0.7, -1.2, -2.0]
        let blurs = speeds.map { blur(atSpeed: $0) }
        XCTAssertEqual(blurs, blurs.sorted())
    }

    func testItIsBoundedSoAFlickDoesNotEraseTheScreen() {
        XCTAssertLessThanOrEqual(blur(atSpeed: -50), 1)
        XCTAssertLessThan(blur(atSpeed: -50) - blur(atSpeed: -3), 0.25)
    }
}
