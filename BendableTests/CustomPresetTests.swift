import XCTest
@testable import Bendable

final class CustomPresetTests: XCTestCase {
    func testMacDuoUsesCaptureAndMovesContinuouslyWithTheHinge() {
        let preset = MacDuoPreset()
        let context = AnimationContext()
        let open = preset.frame(progress: 1, velocity: 0, direction: .closing, context: context)
        let middle = preset.frame(progress: 0.5, velocity: 0, direction: .closing, context: context)
        let closed = preset.frame(progress: 0, velocity: 0, direction: .closing, context: context)

        XCTAssertTrue(preset.requiresScreenCapture)
        XCTAssertTrue(open.isIdentity)
        XCTAssertGreaterThan(middle.foldAngle, 0)
        XCTAssertGreaterThan(middle.perspective, 0)
        XCTAssertGreaterThan(middle.blur, 0)
        XCTAssertEqual(closed.brightness, 0, accuracy: 0.0001)
    }

    func testMacDuoOpeningExactlyRetracesClosing() {
        let preset = MacDuoPreset()
        let context = AnimationContext()
        let closing = preset.frame(progress: 0.47, velocity: 0, direction: .closing, context: context)
        let opening = preset.frame(progress: 0.47, velocity: 0, direction: .opening, context: context)
        XCTAssertEqual(closing, opening)
    }

    func testSunsetIsProceduralCaptureFreeAndTracksProgressDirectly() {
        let preset = SunsetHDRPreset()
        let context = AnimationContext(captureAvailable: false)
        let frame = preset.frame(progress: 0.36, velocity: 0, direction: .closing, context: context)

        XCTAssertFalse(preset.requiresScreenCapture)
        XCTAssertFalse(frame.usesCapturedImage)
        XCTAssertEqual(frame.proceduralEffect, .sunsetHDR)
        XCTAssertEqual(frame.effectProgress, 0.64, accuracy: 0.0001)
    }

    func testSunsetOpeningExactlyRetracesClosing() {
        let preset = SunsetHDRPreset()
        let context = AnimationContext()
        let closing = preset.frame(progress: 0.41, velocity: -0.3, direction: .closing, context: context)
        let opening = preset.frame(progress: 0.41, velocity: 0.3, direction: .opening, context: context)
        XCTAssertEqual(closing, opening)
    }

    func testCustomControlsAreExposedExactly() {
        XCTAssertEqual(MacDuoPreset().supportedControls, [.perspective, .blur, .dimming, .strength])
        XCTAssertEqual(
            SunsetHDRPreset().supportedControls,
            [.sunSize, .glow, .exposure, .warmth, .horizon, .darkness]
        )
    }
}
