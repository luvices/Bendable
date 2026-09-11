import Foundation
import simd

/// The flagship preset: the picture goes on standing at the angle the lid was resting
/// at, while the lid itself folds down out from under it.
///
/// Closing a laptop swings the top edge of the panel toward you and down, so an
/// untouched screen foreshortens: it squashes, and the near top edge splays wider. The
/// preset draws the desktop rotated the opposite way, top receding, by exactly the
/// angle the lid has turned. On the panel that looks like a picture tipping away. Seen
/// from where you are sitting the two rotations cancel, and what reaches your eye is a
/// screen that has not moved at all.
///
/// Two things have to hold or the illusion goes, and each one has been wrong here at
/// least once.
///
/// The direction. The rotation is *against* the lid, which means the rendered top
/// recedes while the physical top approaches. Turn the picture the same way the lid is
/// already going and the eye sees the fold twice: the screen appears to fall inward as
/// it shuts.
///
/// The size. One degree of correction per degree the hinge has swept, no more. This
/// used to map a narrow band onto a fuller sweep so a small movement produced a big
/// fold, which is the right instinct for a preset that decorates the movement and
/// exactly wrong for one that cancels it. Over-correcting does not read as a stronger
/// effect, it reads as the screen tipping backwards of its own accord.
///
/// The rest is grading, all of it strongest at the receding edge: focus goes first,
/// then colour washes out the way an LCD does at a grazing angle, then the light goes.
/// The corners round off as the panel leaves the bezel, so it stops being "the screen"
/// and becomes an object sitting in the dark.
///
/// Everything is driven from `progress` with no internal timeline, which is what makes
/// reversing direction mid-movement free: the state at any angle depends only on that
/// angle.
struct FoldPreset: AnimationPreset {
    static let id = "fold"
    let name = "Fold"
    let summary = "The desktop stays standing where it was while the lid folds away under it."
    let requiresScreenCapture = true
    let supportedControls: PresetControl = [
        .perspective, .tilt, .blur, .variableBlur, .washout, .corners, .dimming,
    ]

    /// Seconds of look-ahead applied from the measured hinge velocity.
    ///
    /// Sensor reports land a frame or so after the movement itself, and the frame we
    /// draw is shown one refresh later again. Leading by a fraction of that removes
    /// most of the perceived lag; it is capped hard so a fast flick cannot run the
    /// animation past where the lid actually is.
    private let velocityLead = 0.016
    private let maxLeadProgress = 0.05

    /// Where the correction stops tracking one for one.
    ///
    /// Up to here it is exact. Past it the panel is far enough off the plane that
    /// holding the picture upright would squeeze it into a sliver at the top of the
    /// frame, so the rest of the travel is compressed. Easing rather than clipping,
    /// because a hard stop leaves the picture frozen through the last of the close,
    /// which is when the lid is moving fastest.
    private let linearTiltLimit = 60.0
    private let maximumTilt = 85.0

    func frame(
        progress: Double,
        velocity: Double,
        direction: HingeDirection,
        context: AnimationContext
    ) -> FrameDescription {
        let intensity = clamp(context.intensity(for: direction), 0, 1)
        let lead = clamp(-velocity * velocityLead, -maxLeadProgress, maxLeadProgress)
        let closure = clamp(1 - progress + lead, 0, 1)

        if context.reduceMotion {
            return ReduceMotionFallback.frame(closure: closure, intensity: intensity)
        }

        let tuning = context.tuning
        var frame = FrameDescription()
        frame.usesCapturedImage = context.captureAvailable
        frame.opacity = 1

        // Hinged along the bottom edge, like the panel.
        frame.foldPosition = 0

        // The degrees the lid has actually swept since the effect took hold, which is
        // exactly what has to be undone. Anything else here breaks the cancellation.
        let swept = closure * context.hingeTravelDegrees * lerp(0.55, 1.0, intensity) * tuning.tilt
        // Positive, so the rendered top recedes while the real one is swinging toward
        // the viewer. Equal and opposite is what leaves the picture apparently still.
        frame.foldAngle = Self.softLimited(
            swept, linearUpTo: linearTiltLimit, ceiling: maximumTilt
        ) * .pi / 180
        // The camera has to sit where a person actually sits, or the counter rotation
        // is the inverse of a projection nobody is looking through and the picture
        // drifts instead of holding still.
        frame.perspective = lerp(0.55, 1.0, intensity) * tuning.perspective

        // Focus goes early and fast at the receding edge; by two-thirds closed that end
        // of the screen is fields of colour while the hinge end is still readable.
        let defocus = Easing.easeOutQuad(normalize(closure, in: 0.30...0.88))
        // Motion blur, and it is not decoration. A lid is shut in well under a second,
        // so the panel can turn a degree and a half between one refresh and the next,
        // and a large change per frame reads as stepping no matter how evenly it is
        // interpolated. Film has the same problem and the same answer. It scales with
        // speed, so a lid moved slowly stays sharp, which is exactly when there is no
        // stepping to hide.
        let motionBlur = clamp(abs(velocity) * 0.22, 0, 0.45)
        frame.blur = clamp((defocus * 0.85 + motionBlur) * intensity * tuning.blur, 0, 1)

        // The gradient is steepest early on, when the difference between the two ends
        // of the panel is the whole illusion, and evens out as the screen goes dark.
        frame.blurGradient = clamp(
            lerp(1.0, 0.5, Easing.smoothstep(normalize(closure, in: 0.55...0.95)))
                * intensity * tuning.variableBlur,
            0, 1
        )

        // Washout leads the dimming, the way a real panel goes milky before it goes out.
        frame.wash = Easing.easeOutQuad(normalize(closure, in: 0.30...0.88)) * intensity * tuning.washout

        // The rounding appears as the panel lifts away from the bezel and is held back
        // at the very start so the overlay cannot pop when it first appears.
        frame.cornerRadius =
            Easing.smoothstep(normalize(closure, in: 0.0...0.28)) * 0.085 * intensity * tuning.corners

        // Started early and taken all the way down. The panel is fading into black, so
        // holding it bright until the last moment leaves it reading as a lit screen
        // sitting on a dark one rather than as a screen going out.
        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.30...0.94)) * tuning.dimming
        frame.brightness = clamp(1 - dim, 0, 1)

        // Light falls off along the panel with distance, all the way to nothing. The
        // far edge has to reach the same black the overlay is painted on, or the panel
        // ends in a visible seam rather than merging with its own background.
        frame.edgeOcclusion = Easing.easeOutQuad(normalize(closure, in: 0.0...0.30)) * intensity
        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.3...0.9)) * 0.55 * intensity

        return frame
    }

    /// Identity below `linearUpTo`, then asymptotic to `ceiling`.
    ///
    /// Clipping instead would leave the panel visibly frozen for the last part of the
    /// close, which is exactly when the lid is moving fastest.
    static func softLimited(_ value: Double, linearUpTo: Double, ceiling: Double) -> Double {
        guard value > linearUpTo else { return max(value, 0) }
        let headroom = ceiling - linearUpTo
        guard headroom > 0 else { return ceiling }
        return linearUpTo + headroom * (1 - exp(-(value - linearUpTo) / headroom))
    }
}

/// Shared simplification for every spatial preset when Reduce Motion is on.
enum ReduceMotionFallback {
    static func frame(closure: Double, intensity: Double) -> FrameDescription {
        var frame = FrameDescription()
        frame.usesCapturedImage = false
        // A single monotonic ramp, so there is no movement and no flashing.
        frame.opacity = Easing.smoothstep(normalize(closure, in: 0.1...0.95)) * clamp(intensity, 0, 1)
        frame.brightness = 0
        return frame
    }

    /// Identity below `linearUpTo`, then asymptotic to `ceiling`.
    ///
    /// Clipping instead would leave the panel visibly frozen for the last part of the
    /// close, which is exactly when the lid is moving fastest.
    static func softLimited(_ value: Double, linearUpTo: Double, ceiling: Double) -> Double {
        guard value > linearUpTo else { return max(value, 0) }
        let headroom = ceiling - linearUpTo
        guard headroom > 0 else { return ceiling }
        return linearUpTo + headroom * (1 - exp(-(value - linearUpTo) / headroom))
    }
}
