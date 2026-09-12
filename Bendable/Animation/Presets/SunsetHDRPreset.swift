import Foundation

/// A procedural sky whose entire state is a pure function of hinge progress.
/// The Metal shader supplies the sun, bloom, haze and dither; no capture or video is
/// loaded, and direction is deliberately irrelevant so opening is an exact reversal.
struct SunsetHDRPreset: AnimationPreset {
    static let id = "sunset-hdr"
    let name = "Sunset HDR"
    let summary = "Daylight descends through a glowing sunset into blue twilight."
    let requiresScreenCapture = false
    let thumbnailProgress = 0.43
    let supportedControls: PresetControl = [
        .sunSize, .glow, .exposure, .warmth, .horizon, .darkness,
    ]

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let closure = clamp(1 - progress, 0, 1)
        let intensity = clamp(context.intensity(for: direction), 0, 1)

        if context.reduceMotion {
            return ReduceMotionFallback.frame(closure: closure, intensity: intensity)
        }

        var frame = FrameDescription()
        frame.usesCapturedImage = false
        frame.proceduralEffect = .sunsetHDR
        frame.effectProgress = closure
        frame.sunSize = context.tuning.sunSize
        frame.glow = context.tuning.glow
        frame.exposure = context.tuning.exposure
        frame.warmth = context.tuning.warmth
        frame.horizon = context.tuning.horizon
        frame.darkness = context.tuning.darkness
        // Fade the generated sky over the real desktop during the first few degrees,
        // avoiding a flash when the overlay engages. Thereafter it is fully opaque.
        frame.opacity = Easing.smoothstep(normalize(closure, in: 0.005...0.10)) * intensity
        frame.brightness = closure >= 0.995 ? 0 : 1
        return frame
    }
}
