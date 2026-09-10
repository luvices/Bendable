import Foundation

/// Two opposing bars meeting at the horizontal centre line.
struct ShutterPreset: AnimationPreset {
    static let id = "shutter"
    let name = "Shutter"
    let summary = "Bars close in from the top and bottom."
    let supportedControls: PresetControl = .dimming

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let intensity = clamp(context.intensity(for: direction), 0, 1)
        let closure = 1 - progress

        if context.reduceMotion {
            return ReduceMotionFallback.frame(closure: closure, intensity: intensity)
        }

        var frame = FrameDescription()
        frame.usesCapturedImage = false
        frame.brightness = 0
        frame.opacity = context.tuning.dimming
        let openness = 1 - Easing.easeInOutCubic(normalize(closure, in: 0.02...0.97))
        frame.mask = .shutter(openness: lerp(1, openness, intensity))
        return frame
    }
}
