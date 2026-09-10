import Foundation

/// Brightness only. Works without screen recording permission and is the automatic
/// substitute when Reduce Motion is enabled.
struct FadePreset: AnimationPreset {
    static let id = "fade"
    let name = "Fade"
    let summary = "A plain dim to black. No screen recording needed."

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let intensity = clamp(context.intensity(for: direction), 0, 1)
        var frame = FrameDescription()
        frame.usesCapturedImage = false
        frame.brightness = 0
        frame.opacity = Easing.easeInOutCubic(normalize(1 - progress, in: 0.05...0.95))
            * intensity * context.tuning.dimming
        return frame
    }
}
