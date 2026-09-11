import Foundation

/// The desktop drops straight back into the dark, keeping square to the viewer.
///
/// No rotation at all, which is the point of it: Fold and Crease both work by turning
/// the picture, and this is the one that answers the lid without ever tilting. The
/// image shrinks about its own centre as though the screen were retreating down a
/// shaft, and the surround it leaves behind is the black the overlay sits on.
///
/// Scale is eased rather than linear because apparent size falls off with the square
/// of distance: a linear shrink reads as a lurch at the end.
struct RecedePreset: AnimationPreset {
    static let id = "recede"
    let name = "Recede"
    let summary = "The desktop drops straight back into the dark, square to you the whole way."
    let requiresScreenCapture = true
    // Late to start, so the shared sample point would show an untouched desktop.
    let thumbnailProgress = 0.34
    let supportedControls: PresetControl = [.blur, .variableBlur, .washout, .corners, .dimming]

    /// How far back it goes. Below about a third the picture is too small to read as a
    /// screen and the effect turns into a logo animation.
    private let smallestScale = 0.42

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let intensity = clamp(context.intensity(for: direction), 0, 1)
        let closure = clamp(1 - progress, 0, 1)

        if context.reduceMotion {
            return ReduceMotionFallback.frame(closure: closure, intensity: intensity)
        }

        let tuning = context.tuning
        var frame = FrameDescription()
        frame.usesCapturedImage = context.captureAvailable
        frame.opacity = 1

        let travelled = Easing.easeInOutCubic(closure) * intensity
        let size = lerp(1, smallestScale, travelled)
        frame.scale = SIMD2(Float(size), Float(size))

        // The corners round off early, so it stops reading as a cropped screenshot and
        // starts reading as an object with edges.
        frame.cornerRadius =
            Easing.smoothstep(normalize(closure, in: 0.0...0.35)) * 0.10 * intensity * tuning.corners

        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.35...0.95))
        let motionBlur = clamp(abs(velocity) * 0.18, 0, 0.35)
        frame.blur = clamp((defocus * 0.7 + motionBlur) * intensity * tuning.blur, 0, 1)
        // Nothing is turning away, so there is no near edge to keep sharp. The gradient
        // is still offered because a little of it reads as depth of field.
        frame.blurGradient = clamp(0.45 * intensity * tuning.variableBlur, 0, 1)

        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.4...0.95)) * intensity * tuning.washout

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.25...0.96)) * tuning.dimming
        frame.brightness = clamp(1 - dim, 0, 1)

        // Heavier than the turning presets get. With no foreshortening to sell the
        // distance, the darkening at the edges is doing that work on its own.
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.1...0.9)) * 0.7 * intensity

        return frame
    }
}
