import XCTest
@testable import Bendable

final class AnimationPresetTests: XCTestCase {
    private let context = AnimationContext()

    private func frames(
        _ preset: any AnimationPreset, progresses: [Double], context: AnimationContext? = nil
    ) -> [FrameDescription] {
        progresses.map {
            preset.frame(progress: $0, velocity: 0, direction: .closing, context: context ?? self.context)
        }
    }

    func testEveryPresetIsANoOpWhileFullyOpen() {
        for preset in AnimationPresetCatalog.all {
            let frame = preset.frame(progress: 1, velocity: 0, direction: .closing, context: context)
            XCTAssertLessThanOrEqual(frame.blur, 0.001, "\(preset.id) blurs a fully open lid")
            XCTAssertEqual(frame.foldAngle, 0, accuracy: 0.001, "\(preset.id) folds a fully open lid")
            XCTAssertEqual(frame.creaseHighlight, 0, accuracy: 0.001, "\(preset.id) lights a flat panel")
            switch frame.mask {
            case .none:
                break
            case let .aperture(_, openness), let .shutter(openness):
                XCTAssertEqual(openness, 1, accuracy: 0.001, "\(preset.id) masks a fully open lid")
            }
        }
    }

    func testFoldIsIdentityAtFullOpenSoTheOverlayCannotFlash() {
        let frame = FoldPreset().frame(progress: 1, velocity: 0, direction: .closing, context: context)
        XCTAssertTrue(frame.isIdentity)
    }

    func testCreaseTracksTheHingeDegreeForDegree() {
        var calibrated = context
        calibrated.hingeTravelDegrees = 120
        let halfway = CreasePreset().frame(
            progress: 0.5, velocity: 0, direction: .closing, context: calibrated
        )
        XCTAssertEqual(halfway.foldAngle * 180 / .pi, 60, accuracy: 0.5)

        calibrated.hingeTravelDegrees = 90
        let narrower = CreasePreset().frame(
            progress: 0.5, velocity: 0, direction: .closing, context: calibrated
        )
        XCTAssertEqual(narrower.foldAngle * 180 / .pi, 45, accuracy: 0.5)
    }

    func testCreaseFoldsThroughTheMiddleWhileFoldHingesAtTheEdge() {
        XCTAssertEqual(
            CreasePreset().frame(progress: 0.5, velocity: 0, direction: .closing, context: context)
                .foldPosition, 0.5
        )
        XCTAssertEqual(
            FoldPreset().frame(progress: 0.5, velocity: 0, direction: .closing, context: context)
                .foldPosition, 0
        )
    }

    func testTheCreaseHighlightPeaksMidFoldAndVanishesAtBothEnds() {
        let samples = stride(from: 1.0, through: 0.0, by: -0.05).map {
            CreasePreset().frame(progress: $0, velocity: 0, direction: .closing, context: context)
                .creaseHighlight
        }
        let peak = samples.max() ?? 0
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.0001, "A flat panel has no crease to light")
        XCTAssertEqual(
            CreasePreset().frame(progress: 0, velocity: 0, direction: .closing, context: context)
                .creaseHighlight,
            0, accuracy: 0.0001, "A dark panel emits nothing"
        )
        XCTAssertGreaterThan(peak, 0.3)
        let peakIndex = samples.firstIndex(of: peak) ?? 0
        XCTAssertTrue((1..<(samples.count - 1)).contains(peakIndex), "Peak landed at \(peakIndex)")
    }

    /// The order the three ramps arrive in is the whole character of the preset.
    /// Geometry first, or it reads as the screen simply switching off; light last, or
    /// there is nothing left to see the fold by.
    func testFoldLeadsWithGeometryThenSoftensThenDarkens() {
        func frame(_ progress: Double) -> FrameDescription {
            FoldPreset().frame(progress: progress, velocity: 0, direction: .closing, context: context)
        }

        // A fifth of the way down: tipping, still sharp, still lit.
        let early = frame(0.8)
        XCTAssertGreaterThan(early.foldAngle * 180 / .pi, 10)
        XCTAssertLessThan(early.blur, 0.1)
        XCTAssertEqual(early.brightness, 1, accuracy: 0.001)

        // Halfway: well tipped and visibly soft, but not yet going dark.
        let midway = frame(0.5)
        XCTAssertGreaterThan(midway.foldAngle * 180 / .pi, 35)
        XCTAssertGreaterThan(midway.blur, 0.15)
        XCTAssertGreaterThan(midway.brightness, 0.85)

        // Near the stop: dark.
        XCTAssertLessThan(frame(0.05).brightness, 0.15)
    }

    func testFoldBlurIsMonotonicAndFullyDarkAtTheStop() {
        let frames = stride(from: 1.0, through: 0.0, by: -0.02).map {
            FoldPreset().frame(progress: $0, velocity: 0, direction: .closing, context: context)
        }
        let blurs = frames.map(\.blur)
        XCTAssertEqual(blurs, blurs.sorted())
        let brightnesses = frames.map(\.brightness)
        XCTAssertEqual(brightnesses, brightnesses.sorted().reversed())
        XCTAssertTrue(frames.last?.isOpaqueBlack ?? false)
    }

    func testFoldHingesAtTheBottomEdgeLikeThePanel() {
        for progress in stride(from: 1.0, through: 0.0, by: -0.1) {
            let frame = FoldPreset().frame(
                progress: progress, velocity: 0, direction: .closing, context: context
            )
            XCTAssertEqual(frame.foldPosition, 0, "The panel hinges at its bottom edge")
            XCTAssertEqual(frame.creaseHighlight, 0, "Fold has no crease to light")
            XCTAssertEqual(frame.curvature, 0, "The image stays a rigid rectangle")
        }
    }

    func testFoldTiltIsProportionalToTravelAndCappedShortOfEdgeOn() {
        let tilts = stride(from: 1.0, through: 0.0, by: -0.05).map {
            FoldPreset().frame(progress: $0, velocity: 0, direction: .closing, context: context)
                .foldAngle * 180 / .pi
        }
        var calibrated = context
        calibrated.hingeTravelDegrees = 100
        func tilt(at progress: Double) -> Double {
            FoldPreset().frame(progress: progress, velocity: 0, direction: .closing, context: calibrated)
                .foldAngle * 180 / .pi
        }

        XCTAssertEqual(tilts, tilts.sorted())
        XCTAssertEqual(tilt(at: 1), 0, accuracy: 0.0001)

        // Degree for degree with the hinge while the panel is still comfortably a
        // screen: 30° of lid travel turns the render 30°.
        XCTAssertEqual(tilt(at: 0.7), 30, accuracy: 0.5)
        XCTAssertEqual(tilt(at: 0.5), 50, accuracy: 0.5)

        // Past that it eases into a ceiling rather than clipping, which would leave the
        // panel visibly frozen for the last of the close.
        XCTAssertGreaterThan(tilt(at: 0.1), tilt(at: 0.2))
        XCTAssertGreaterThan(tilt(at: 0), tilt(at: 0.1))
        XCTAssertLessThan(tilt(at: 0), 85, "Edge-on stops reading as a screen")
    }

    func testFoldRoundsItsCornersOnlyOnceThePanelHasMoved() {
        let atRest = FoldPreset().frame(
            progress: 1, velocity: 0, direction: .closing, context: context
        )
        XCTAssertEqual(atRest.cornerRadius, 0, "Rounding at full open would pop the overlay")

        let moved = FoldPreset().frame(
            progress: 0.6, velocity: 0, direction: .closing, context: context
        )
        XCTAssertGreaterThan(moved.cornerRadius, 0.05)
    }

    func testFoldAngleIncreasesMonotonicallyAsTheLidCloses() {
        let progresses = stride(from: 1.0, through: 0.0, by: -0.05).map { $0 }
        let angles = frames(CreasePreset(), progresses: progresses).map(\.foldAngle)
        XCTAssertEqual(angles, angles.sorted())
        XCTAssertGreaterThan(angles.last ?? 0, 1.0)
    }

    func testFoldGoesFullyDarkBeforeTheLidIsShut() {
        let frame = FoldPreset().frame(progress: 0, velocity: 0, direction: .closing, context: context)
        XCTAssertEqual(frame.brightness, 0, accuracy: 0.001)
        XCTAssertTrue(frame.isOpaqueBlack)
    }

    func testFoldIsAPureFunctionOfItsInputs() {
        let a = FoldPreset().frame(progress: 0.42, velocity: -0.8, direction: .closing, context: context)
        let b = FoldPreset().frame(progress: 0.42, velocity: -0.8, direction: .closing, context: context)
        XCTAssertEqual(a, b)
    }

    func testFoldLeadsTheHingeWhenClosingQuickly() {
        let still = CreasePreset().frame(progress: 0.5, velocity: 0, direction: .closing, context: context)
        let moving = CreasePreset().frame(progress: 0.5, velocity: -2.0, direction: .closing, context: context)
        XCTAssertGreaterThan(moving.foldAngle, still.foldAngle)
        // The lead is bounded so a flick cannot throw the image past the lid.
        XCTAssertLessThan(moving.foldAngle - still.foldAngle, 0.1)
    }

    func testIntensityScalesTheEffect() {
        var gentle = context
        gentle.closingIntensity = 0
        let soft = CreasePreset().frame(progress: 0.3, velocity: 0, direction: .closing, context: gentle)
        let full = CreasePreset().frame(progress: 0.3, velocity: 0, direction: .closing, context: context)
        XCTAssertLessThan(soft.foldAngle, full.foldAngle)
        XCTAssertLessThan(soft.vignette, full.vignette)
    }

    func testDirectionSelectsTheMatchingIntensity() {
        var asymmetric = context
        asymmetric.closingIntensity = 1
        asymmetric.openingIntensity = 0.2
        let closing = FoldPreset().frame(progress: 0.5, velocity: 0, direction: .closing, context: asymmetric)
        let opening = FoldPreset().frame(progress: 0.5, velocity: 0, direction: .opening, context: asymmetric)
        XCTAssertGreaterThan(closing.foldAngle, opening.foldAngle)
    }

    func testReduceMotionRemovesSpatialEffects() {
        var reduced = context
        reduced.reduceMotion = true
        for preset in AnimationPresetCatalog.all {
            for progress in stride(from: 1.0, through: 0.0, by: -0.1) {
                let frame = preset.frame(
                    progress: progress, velocity: -1, direction: .closing, context: reduced
                )
                XCTAssertEqual(frame.foldAngle, 0, "\(preset.id) folds under Reduce Motion")
                XCTAssertEqual(frame.blur, 0, "\(preset.id) blurs under Reduce Motion")
                XCTAssertEqual(frame.mask, .none, "\(preset.id) masks under Reduce Motion")
            }
        }
    }

    func testReduceMotionOpacityRampIsMonotonicSoNothingFlashes() {
        var reduced = context
        reduced.reduceMotion = true
        let opacities = stride(from: 1.0, through: 0.0, by: -0.02)
            .map { FoldPreset().frame(progress: $0, velocity: 0, direction: .closing, context: reduced).opacity }
        XCTAssertEqual(opacities, opacities.sorted())
    }

    func testPresetsWithoutCaptureNeverRequestTheDesktopImage() {
        var noCapture = context
        noCapture.captureAvailable = false
        for preset in AnimationPresetCatalog.all where !preset.requiresScreenCapture {
            let frame = preset.frame(progress: 0.4, velocity: 0, direction: .closing, context: noCapture)
            XCTAssertFalse(frame.usesCapturedImage, "\(preset.id) needs capture it did not declare")
        }
    }

    func testMaskPresetsCloseFullyByTheEndOfTravel() {
        for preset in [AperturePreset(), ShutterPreset()] as [any AnimationPreset] {
            let frame = preset.frame(progress: 0, velocity: 0, direction: .closing, context: context)
            switch frame.mask {
            case let .aperture(_, openness), let .shutter(openness):
                XCTAssertEqual(openness, 0, accuracy: 0.001, "\(preset.id) never fully closes")
            case .none:
                XCTFail("\(preset.id) produced no mask at full closure")
            }
        }
    }

    func testCatalogLookupFallsBackToFold() {
        XCTAssertEqual(AnimationPresetCatalog.preset(id: "does-not-exist").id, FoldPreset.id)
        XCTAssertEqual(AnimationPresetCatalog.all.first?.id, FoldPreset.id)
        XCTAssertEqual(Set(AnimationPresetCatalog.all.map(\.id)).count, AnimationPresetCatalog.all.count)
    }
}


final class SoftLimitTests: XCTestCase {
    func testItIsExactlyIdentityBelowTheLinearLimit() {
        for value in stride(from: 0.0, through: 55.0, by: 5.0) {
            XCTAssertEqual(
                FoldPreset.softLimited(value, linearUpTo: 55, ceiling: 80), value, accuracy: 0.0001
            )
        }
    }

    func testItApproachesTheCeilingWithoutEverReachingIt() {
        let large = FoldPreset.softLimited(400, linearUpTo: 55, ceiling: 80)
        XCTAssertLessThan(large, 80)
        XCTAssertGreaterThan(large, 79)
    }

    func testItStaysStrictlyIncreasing() {
        var previous = -1.0
        for value in stride(from: 0.0, through: 200.0, by: 2.0) {
            let limited = FoldPreset.softLimited(value, linearUpTo: 55, ceiling: 80)
            XCTAssertGreaterThan(limited, previous, "flat at \(value)")
            previous = limited
        }
    }
}
