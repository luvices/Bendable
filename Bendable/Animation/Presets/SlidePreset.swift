import Foundation

/// The desktop slides down behind the hinge, the way a card goes into a slot.
///
/// The only preset that moves the picture rather than deforming it, which makes it the
/// calmest of them: nothing keystones, nothing softens out of recognition, the image
/// simply leaves. It suits people who find the turning presets busy.
///
/// The travel is exactly the height of the frame and the easing accelerates all the
/// way, so the picture leaves at the moment the lid shuts and not before. Overshooting
/// the distance, or easing to a stop, both spend the last of the close on an empty
/// screen, which reads as the effect having finished early.
struct SlidePreset: AnimationPreset {
    static let id = "slide"
    let name = "Slide"
    let summary = "The desktop slides down out of sight, behind the hinge."
    let requiresScreenCapture = true
    // Late to start, so the shared sample point would show an untouched desktop.
    let thumbnailProgress = 0.3
    let supportedControls: PresetControl = [.blur, .washout, .corners, .dimming]

    /// In half-heights, so 2 clears the frame exactly and nothing more is needed.
    private let travel = 2.0

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

        // Accelerating away rather than easing to a halt, so it reads as something
        // dropped rather than parked, and so it is still moving as it goes.
        let distance = Easing.easeInCubic(closure) * travel * intensity
        frame.translate = SIMD2(0, Float(-distance))

        frame.cornerRadius =
            Easing.smoothstep(normalize(closure, in: 0.0...0.25)) * 0.09 * intensity * tuning.corners

        // Mostly motion blur here. There is no defocus to speak of, because the picture
        // is not going anywhere the eye cannot follow, it is just going.
        let motionBlur = clamp(abs(velocity) * 0.30, 0, 0.5)
        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.6...1.0)) * 0.35
        frame.blur = clamp((defocus + motionBlur) * intensity * tuning.blur, 0, 1)

        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.55...1.0)) * 0.7 * intensity * tuning.washout

        // Late and shallow. The picture is meant to leave the frame, not go out in it.
        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.55...1.0)) * 0.85 * tuning.dimming
        frame.brightness = clamp(1 - dim, 0, 1)

        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.5...1.0)) * 0.4 * intensity

        return frame
    }
}
