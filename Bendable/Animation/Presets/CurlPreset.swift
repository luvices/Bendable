import Foundation

/// The top of the desktop curls over and away, like a sheet lifting off a desk.
///
/// Same machinery as Crease, used for the opposite purpose. Crease puts a hard bend
/// through the middle of a rigid sheet; this puts a soft one near the top and leans on
/// the shader's bow, so the picture stays flat across most of its height and only the
/// last strip rolls over. That reads as paper rather than as a hinge.
///
/// The crease is high rather than central because a curl low on the image takes the
/// content with it and there is nothing left to look at.
struct CurlPreset: AnimationPreset {
    static let id = "curl"
    let name = "Curl"
    let summary = "The top edge curls over and away, the way a sheet of paper lifts."
    let requiresScreenCapture = true
    // Late to start, so the shared sample point would show an untouched desktop.
    let thumbnailProgress = 0.46
    let supportedControls: PresetControl = [
        .perspective, .tilt, .blur, .variableBlur, .washout, .corners, .dimming,
    ]

    private let creasePosition = 0.68
    /// Past a right angle the curled strip is edge-on and contributes nothing but a
    /// dark band, so the roll stops there and the rest of the close is graded.
    private let maximumRoll = 95.0

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
        frame.foldPosition = creasePosition

        // Eased, not linear. Paper does not begin to lift the moment it is touched: it
        // resists, gives, and then goes over quickly.
        let rolled = Easing.easeInOutCubic(closure) * maximumRoll
            * lerp(0.6, 1.0, intensity) * tuning.tilt
        frame.foldAngle = min(rolled, maximumRoll) * .pi / 180
        frame.perspective = lerp(0.5, 1.0, intensity) * tuning.perspective

        // The bow is the whole difference between this and Crease. It peaks while the
        // strip is going over and flattens again once it is edge-on.
        frame.curvature = sin(min(frame.foldAngle, .pi)) * 0.16 * intensity
        frame.creaseHighlight = sin(min(frame.foldAngle, .pi)) * 0.30 * intensity

        frame.cornerRadius =
            Easing.smoothstep(normalize(closure, in: 0.0...0.3)) * 0.06 * intensity * tuning.corners

        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.45...0.95))
        let motionBlur = clamp(abs(velocity) * 0.20, 0, 0.40)
        frame.blur = clamp((defocus * 0.75 + motionBlur) * intensity * tuning.blur, 0, 1)
        // Held high: the flat part of the sheet stays readable while the curl softens,
        // which is what makes the two parts look like one piece of material.
        frame.blurGradient = clamp(0.9 * intensity * tuning.variableBlur, 0, 1)

        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.45...0.95)) * intensity * tuning.washout

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.5...0.98)) * tuning.dimming
        frame.brightness = clamp(1 - dim, 0, 1)

        frame.edgeOcclusion = Easing.easeOutQuad(normalize(closure, in: 0.0...0.4)) * intensity
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.4...0.95)) * 0.5 * intensity

        return frame
    }
}
