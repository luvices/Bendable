import Foundation
import simd

/// The desktop behaves like a sheet creased across its middle, with the upper half
/// rotating away from you as the lid comes down.
///
/// The geometry is deliberately literal, a rigid panel hinged along a crease and
/// projected through a camera, and the panel turns by the angle the hinge has actually
/// swept, so the two stay locked together rather than the animation following
/// a curve of its own.
struct CreasePreset: AnimationPreset {
    static let id = "crease"
    let name = "Crease"
    let summary = "The desktop creases across the middle and folds away in perspective."
    let requiresScreenCapture = true
    let supportedControls: PresetControl = [.perspective, .tilt, .blur, .corners, .dimming]

    /// Where the crease sits, measured from the bottom of the image.
    let creasePosition: Double

    private let velocityLead = 0.016
    private let maxLeadProgress = 0.05

    init(creasePosition: Double = 0.5) {
        self.creasePosition = creasePosition
    }

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
        frame.foldPosition = creasePosition

        // One degree of hinge travel turns the panel by one degree.
        let sweptDegrees = closure * context.hingeTravelDegrees * lerp(0.6, 1.0, intensity) * tuning.tilt
        frame.foldAngle = sweptDegrees * .pi / 180
        frame.perspective = lerp(0.5, 1.0, intensity) * tuning.perspective
        frame.cornerRadius =
            Easing.smoothstep(normalize(closure, in: 0.0...0.3)) * 0.07 * intensity * tuning.corners

        // The crease rounds off as it bends and flattens again at either extreme.
        let bend = sin(min(frame.foldAngle, .pi))
        frame.curvature = bend * 0.07 * intensity

        let defocus = Easing.easeInOutCubic(normalize(closure, in: 0.72...0.99))
        let motionBlur = clamp(abs(velocity) * 0.20, 0, 0.40)
        frame.blur = clamp((defocus * 0.8 + motionBlur) * intensity * tuning.blur, 0, 1)

        let dim = Easing.easeInOutCubic(normalize(closure, in: 0.66...1.0)) * tuning.dimming
        frame.brightness = clamp(1 - dim, 0, 1)

        // The highlight is light from the panel itself, so it dies with the panel
        // rather than surviving as a bright line on an otherwise black screen.
        frame.creaseHighlight = bend * 0.55 * intensity * frame.brightness

        frame.vignette = Easing.smoothstep(normalize(closure, in: 0.35...0.95)) * 0.55 * intensity
        frame.edgeOcclusion = Easing.smoothstep(normalize(closure, in: 0.0...0.55)) * intensity

        return frame
    }
}
