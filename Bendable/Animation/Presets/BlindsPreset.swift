import Foundation

/// Slats close across the screen, each shutting from its own edges inward.
///
/// Like Aperture and Shutter this paints a mask rather than redrawing the desktop, so
/// it needs no Screen Recording permission and works on a machine where the others
/// have to fall back to a plain fade.
///
/// It differs from Shutter in where the black comes from. Shutter closes two bars
/// toward the middle, so the picture survives longest in a band across the centre.
/// This cuts the height into slats that each close independently, so what survives is
/// spread evenly over the whole screen and the last thing you see is the picture as a
/// whole, going out, rather than a strip of it.
struct BlindsPreset: AnimationPreset {
    static let id = "blinds"
    let name = "Blinds"
    let summary = "Slats close down the screen, each one shutting from its edges in."
    let requiresScreenCapture = false
    // Late to start, so the shared sample point would show an untouched desktop.
    let thumbnailProgress = 0.5

    /// Enough to read as slats and not as scanlines. Nine looked like a fault on the
    /// display; six is unmistakably a set of blinds.
    private let slats = 6

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

        var frame = FrameDescription()
        frame.usesCapturedImage = false
        frame.brightness = 0
        frame.opacity = context.tuning.dimming

        // Eased, unlike Aperture. An iris has to close almost linearly because the area
        // it covers grows with the square of its radius. Slats cover in proportion to
        // the number driving them, so the same easing here shuts them within the first
        // few degrees of travel and leaves nothing for the rest of the close.
        let openness = 1 - Easing.easeInOutCubic(normalize(closure, in: 0.0...0.95))
        frame.mask = .blinds(slats: slats, openness: lerp(1, openness, intensity))

        return frame
    }
}
