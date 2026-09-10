import Foundation

/// Converts hinge state into frames, applying user settings and accessibility rules.
///
/// Deliberately synchronous and side-effect free apart from holding the selected
/// preset: the same instance backs the overlay and the settings preview, which is what
/// guarantees the preview shows exactly what the lid will.
@MainActor
final class AnimationEngine {
    private(set) var preset: any AnimationPreset
    var context: AnimationContext

    init(preset: any AnimationPreset = FoldPreset(), context: AnimationContext = AnimationContext()) {
        self.preset = preset
        self.context = context
    }

    func select(presetID: String) {
        preset = AnimationPresetCatalog.preset(id: presetID)
        Log.animation.info("Preset selected: \(self.preset.id, privacy: .public)")
    }

    /// A preset that needs the desktop image but has no capture available degrades to
    /// Fade rather than rendering an empty panel.
    var effectivePreset: any AnimationPreset {
        if preset.requiresScreenCapture && !context.captureAvailable {
            return FadePreset()
        }
        return preset
    }

    func frame(for state: HingeState) -> FrameDescription {
        effectivePreset.frame(
            progress: state.progress,
            velocity: state.velocity,
            direction: state.direction,
            context: context
        )
    }

    /// Evaluates a hypothetical progress value. Used by the preview scrubber and tests.
    func frame(progress: Double, velocity: Double = 0, direction: HingeDirection = .closing) -> FrameDescription {
        effectivePreset.frame(
            progress: clamp(progress, 0, 1), velocity: velocity, direction: direction, context: context
        )
    }

    var needsScreenCapture: Bool {
        preset.requiresScreenCapture
    }

    /// True when the chosen preset is not the one being rendered.
    var isSubstituting: Bool {
        effectivePreset.id != preset.id
    }
}
