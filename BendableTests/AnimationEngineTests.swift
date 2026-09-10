import XCTest
@testable import Bendable

@MainActor
final class AnimationEngineTests: XCTestCase {
    func testEngineRendersTheSelectedPreset() {
        let engine = AnimationEngine()
        engine.select(presetID: ShutterPreset.id)
        let frame = engine.frame(progress: 0.5)
        if case .shutter = frame.mask {} else {
            XCTFail("Expected the shutter mask, got \(frame.mask)")
        }
    }

    func testCapturePresetsDegradeToFadeWithoutPermission() {
        var context = AnimationContext()
        context.captureAvailable = false
        let engine = AnimationEngine(preset: FoldPreset(), context: context)
        XCTAssertEqual(engine.effectivePreset.id, FadePreset.id)

        engine.context.captureAvailable = true
        XCTAssertEqual(engine.effectivePreset.id, FoldPreset.id)
    }

    func testHingeStateAndScrubberProduceIdenticalFrames() {
        let engine = AnimationEngine()
        let state = HingeState(
            angle: 45, progress: 0.37, velocity: -0.8, direction: .closing, isClosed: false, timestamp: 0
        )
        XCTAssertEqual(
            engine.frame(for: state),
            engine.frame(progress: 0.37, velocity: -0.8, direction: .closing)
        )
    }

    func testUniformsMatchTheFrameDescription() {
        var frame = FrameDescription()
        frame.foldAngle = 0.6
        frame.blur = 0.4
        frame.mask = .aperture(blades: 6, openness: 0.25)
        let uniforms = RenderUniforms(frame: frame, aspect: 1.6, hasTexture: false, maxLOD: 10)

        XCTAssertEqual(uniforms.foldAngle, 0.6, accuracy: 0.0001)
        XCTAssertEqual(uniforms.blur, 0.4, accuracy: 0.0001)
        XCTAssertEqual(uniforms.maskKind, 1)
        XCTAssertEqual(uniforms.blades, 6)
        XCTAssertEqual(uniforms.maskOpenness, 0.25, accuracy: 0.0001)
        // No texture uploaded, so the shader must not try to sample one.
        XCTAssertEqual(uniforms.useTexture, 0)
    }

    func testBackdropIsOpaqueOnlyWhenTheDesktopImageIsBeingDrawn() {
        var frame = FrameDescription()
        frame.usesCapturedImage = true
        XCTAssertEqual(RenderUniforms.clearColor(for: frame, hasTexture: true).3, 1, accuracy: 0.0001)
        XCTAssertEqual(RenderUniforms.clearColor(for: frame, hasTexture: false).3, 0, accuracy: 0.0001)

        frame.usesCapturedImage = false
        XCTAssertEqual(RenderUniforms.clearColor(for: frame, hasTexture: true).3, 0, accuracy: 0.0001)
    }
}

@MainActor
final class PresetSubstitutionTests: XCTestCase {
    /// The engine falling back to Fade is correct, but silently is not: it is
    /// indistinguishable from the chosen preset being broken.
    func testSubstitutionIsReportedSoTheInterfaceCanSaySo() {
        var context = AnimationContext()
        context.captureAvailable = false
        let engine = AnimationEngine(preset: FoldPreset(), context: context)

        XCTAssertTrue(engine.isSubstituting)
        XCTAssertEqual(engine.effectivePreset.id, FadePreset.id)

        engine.context.captureAvailable = true
        XCTAssertFalse(engine.isSubstituting)
        XCTAssertEqual(engine.effectivePreset.id, FoldPreset.id)
    }

    func testPresetsThatNeedNoCaptureAreNeverSubstituted() {
        var context = AnimationContext()
        context.captureAvailable = false
        for preset in AnimationPresetCatalog.all where !preset.requiresScreenCapture {
            let engine = AnimationEngine(preset: preset, context: context)
            XCTAssertFalse(engine.isSubstituting, "\(preset.id)")
        }
    }
}
