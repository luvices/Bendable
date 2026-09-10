import Foundation

/// A camera iris closing over the desktop. The blades are drawn as an occluding
/// layer, so the real screen shows through and no capture permission is needed.
struct AperturePreset: AnimationPreset {
    static let id = "aperture"
    let name = "Aperture"
    let summary = "Iris blades close over the screen."
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
        // Close mostly linearly. The visible area falls off with the square of the
        // radius, so an eased radius reads as a snap at the end.
        let openness = 1 - Easing.easeOutQuad(normalize(closure, in: 0.0...0.94))
        frame.mask = .aperture(blades: 6, openness: lerp(1, openness, intensity))
        frame.vignette = Easing.smoothstep(closure) * 0.3 * intensity
        return frame
    }
}
