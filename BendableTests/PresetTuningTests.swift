import XCTest
@testable import Bendable

final class PresetTuningTests: XCTestCase {
    private let midTravel = 0.45

    /// Ramps start at different points in the travel, so a control has to be checked
    /// across the whole of it rather than at one arbitrary angle.
    private func differs(
        _ preset: any AnimationPreset, _ control: PresetControl
    ) -> Bool {
        stride(from: 1.0, through: 0.0, by: -0.05).contains { progress in
            var full = AnimationContext()
            full.tuning[control] = 1
            var off = AnimationContext()
            off.tuning[control] = 0
            return preset.frame(progress: progress, velocity: 0, direction: .closing, context: full)
                != preset.frame(progress: progress, velocity: 0, direction: .closing, context: off)
        }
    }

    func testSubscriptRoundTripsAndClamps() {
        var tuning = PresetTuning.default
        for control in PresetControl.displayOrder {
            tuning[control] = 0.42
            XCTAssertEqual(tuning[control], 0.42, accuracy: 0.0001, control.title)
        }
        tuning[.blur] = 4
        XCTAssertEqual(tuning.blur, 1)
        tuning[.blur] = -2
        XCTAssertEqual(tuning.blur, 0)
    }

    /// The popover builds its sliders from `supportedControls`, so a control listed
    /// there but wired to nothing would render a slider that silently does nothing.
    func testEveryDeclaredControlActuallyChangesTheFrame() {
        for preset in AnimationPresetCatalog.all {
            for control in PresetControl.displayOrder where preset.supportedControls.contains(control) {
                XCTAssertTrue(
                    differs(preset, control),
                    "\(preset.id) declares \(control.title) but ignores it"
                )
            }
        }
    }

    /// And the reverse: a preset must not respond to a control it did not declare,
    /// or the slider for it is simply missing from the interface.
    func testPresetsIgnoreControlsTheyDoNotDeclare() {
        for preset in AnimationPresetCatalog.all {
            for control in PresetControl.displayOrder where !preset.supportedControls.contains(control) {
                XCTAssertFalse(
                    differs(preset, control),
                    "\(preset.id) responds to undeclared \(control.title)"
                )
            }
        }
    }

    func testZeroedTuningLeavesTheScreenAlone() {
        var context = AnimationContext()
        context.tuning = PresetTuning(
            perspective: 0, tilt: 0, blur: 0, variableBlur: 0, washout: 0, corners: 0, dimming: 0
        )
        let frame = FoldPreset().frame(
            progress: midTravel, velocity: 0, direction: .closing, context: context
        )
        XCTAssertEqual(frame.foldAngle, 0, accuracy: 0.0001)
        XCTAssertEqual(frame.blur, 0, accuracy: 0.0001)
        XCTAssertEqual(frame.wash, 0, accuracy: 0.0001)
        XCTAssertEqual(frame.cornerRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(frame.brightness, 1, accuracy: 0.0001)
    }

    func testTuningStillHonoursFullOpenAsANoOp() {
        for preset in AnimationPresetCatalog.all {
            var context = AnimationContext()
            context.tuning = PresetTuning(
                perspective: 1, tilt: 1, blur: 1, variableBlur: 1, washout: 1, corners: 1, dimming: 1
            )
            let frame = preset.frame(progress: 1, velocity: 0, direction: .closing, context: context)
            XCTAssertEqual(frame.blur, 0, accuracy: 0.0001, "\(preset.id)")
            XCTAssertEqual(frame.foldAngle, 0, accuracy: 0.0001, "\(preset.id)")
            XCTAssertEqual(frame.cornerRadius, 0, accuracy: 0.0001, "\(preset.id)")
        }
    }
}

@MainActor
final class PreferencesTuningTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "com.bendable.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testTuningIsKeptPerPresetAndPersists() throws {
        let defaults = try makeDefaults()
        let first = Preferences(defaults: defaults)

        first.presetID = FoldPreset.id
        first.currentTuning.blur = 0.25
        first.presetID = CreasePreset.id
        first.currentTuning.blur = 0.75

        XCTAssertEqual(first.tuning(for: FoldPreset.id).blur, 0.25, accuracy: 0.0001)
        XCTAssertEqual(first.tuning(for: CreasePreset.id).blur, 0.75, accuracy: 0.0001)

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.tuning(for: FoldPreset.id).blur, 0.25, accuracy: 0.0001)
        XCTAssertEqual(second.tuning(for: CreasePreset.id).blur, 0.75, accuracy: 0.0001)
    }

    func testUntouchedPresetsUseTheDefaultTuning() throws {
        let preferences = Preferences(defaults: try makeDefaults())
        XCTAssertEqual(preferences.tuning(for: ShutterPreset.id), .default)
    }

    func testResettingRestoresTheDefaultForThatPresetOnly() throws {
        let preferences = Preferences(defaults: try makeDefaults())
        preferences.setTuning(PresetTuning(blur: 0.1), for: FoldPreset.id)
        preferences.setTuning(PresetTuning(blur: 0.2), for: CreasePreset.id)

        preferences.resetTuning(for: FoldPreset.id)
        XCTAssertEqual(preferences.tuning(for: FoldPreset.id), .default)
        XCTAssertEqual(preferences.tuning(for: CreasePreset.id).blur, 0.2, accuracy: 0.0001)
    }
}
