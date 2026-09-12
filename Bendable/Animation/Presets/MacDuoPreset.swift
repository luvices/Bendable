import Foundation
import simd

/// Holds the captured desktop visually in space while the physical panel closes.
/// Every value is derived from the current hinge sample, so stopping or reversing the
/// lid stops or reverses the image without a separate animation timeline.
struct MacDuoPreset: AnimationPreset {
    static let id = "mac-duo"
    let name = "Mac Duo"
    let summary = "The desktop stays spatially anchored as the MacBook folds closed."
    let requiresScreenCapture = true
    let thumbnailProgress = 0.46
    let supportedControls: PresetControl = [.perspective, .blur, .dimming, .strength]

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let closure = clamp(1 - progress, 0, 1)
        let intensity = clamp(context.intensity(for: direction), 0, 1)
        let strength = context.tuning.strength * intensity

        if context.reduceMotion {
            return ReduceMotionFallback.frame(closure: closure, intensity: strength)
        }

        // The lower edge is the physical hinge. Keeping it fixed while the upper edge
        // recedes is the visual anchor; mild scale compensation prevents the desktop
        // from appearing to collapse toward its centre.
        let spatial = Easing.easeInOutCubic(closure) * strength
        let swept = closure * context.hingeTravelDegrees * strength

        var frame = FrameDescription()
        frame.usesCapturedImage = context.captureAvailable
        frame.foldPosition = 0
        frame.foldAngle = FoldPreset.softLimited(swept, linearUpTo: 58, ceiling: 82) * .pi / 180
        frame.perspective = spatial * context.tuning.perspective
        frame.scale = SIMD2(
            Float(1 + spatial * 0.055),
            Float(1 + spatial * 0.035)
        )
        frame.translate.y = Float(spatial * 0.035)

        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.16...0.92))
        let motionBlur = clamp(abs(velocity) * 0.16, 0, 0.28)
        frame.blur = clamp((defocus * 0.62 + motionBlur) * strength * context.tuning.blur, 0, 1)
        frame.blurGradient = 0.55 * strength

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.24...0.96))
            * context.tuning.dimming * lerp(0.72, 1, strength)
        frame.brightness = clamp(1 - dim, 0, 1)

        // Corners, vignette and distance grading make the panel edges disappear into
        // the black surround instead of leaving a hard transformed rectangle.
        frame.cornerRadius = Easing.smoothstep(normalize(closure, in: 0.05...0.42)) * 0.075 * strength
        frame.edgeOcclusion = Easing.easeOutQuad(normalize(closure, in: 0.08...0.72)) * strength
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.2...0.94)) * 0.76 * strength

        // The endpoint is invariant even at lower strength: a shut lid always meets
        // the same opaque black and opening retraces the exact values in reverse.
        let terminalFade = Easing.smoothstep(normalize(closure, in: 0.90...1.0))
        frame.brightness *= 1 - terminalFade
        return frame
    }
}
