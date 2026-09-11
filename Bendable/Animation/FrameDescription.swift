import Foundation
import simd

/// A geometric cutout applied on top of whatever the preset does with the image.
enum MaskDescription: Sendable, Equatable {
    case none
    /// `openness` 1 = wide open, 0 = fully shut.
    case aperture(blades: Int, openness: Double)
    /// Two bars closing toward the horizontal centre line.
    case shutter(openness: Double)
    /// Slats closing across the whole height, each one shutting from its own edges in.
    case blinds(slats: Int, openness: Double)
}

/// Everything the renderer needs for one frame.
///
/// Presets are pure functions producing this value, which makes them trivially
/// testable and keeps all GPU knowledge in one place.
struct FrameDescription: Sendable, Equatable {
    /// Rotation of the upper panel about the crease, in radians. 0 leaves the image flat.
    var foldAngle: Double = 0
    /// Where the crease sits, measured from the bottom of the image.
    /// 0.5 creases through the middle; 0 hinges the whole image at its bottom edge.
    var foldPosition: Double = 0.5
    /// 0 disables the perspective divide; 1 is the full effect.
    var perspective: Double = 0
    /// How much the panel bows either side of the crease, as a folding display does.
    var curvature: Double = 0
    /// Strength of the light catching the bend.
    var creaseHighlight: Double = 0
    var scale: SIMD2<Float> = .one
    var translate: SIMD2<Float> = .zero
    /// 0...1, mapped to a mip level by the renderer.
    var blur: Double = 0
    /// How much `blur` and `wash` vary along the panel, from the hinge edge to the
    /// edge swinging away. 0 applies them evenly; 1 leaves the hinge edge untouched.
    var blurGradient: Double = 0
    /// Off-axis washout: desaturates and lifts the image toward white, following the
    /// same gradient as the blur. This is what a real panel does as it turns past you.
    var wash: Double = 0
    /// Rounds the corners of the image itself, in units of half the image height.
    /// The rounding travels with the content through whatever transform is applied.
    var cornerRadius: Double = 0
    /// 1 leaves luminance untouched, 0 is black.
    var brightness: Double = 1
    /// Alpha of the whole overlay.
    var opacity: Double = 1
    var vignette: Double = 0
    /// Darkening that grows toward the top edge, standing in for the lid occluding itself.
    var edgeOcclusion: Double = 0
    var mask: MaskDescription = .none
    /// When false the renderer paints flat black instead of the captured desktop,
    /// which is how presets stay useful without screen recording permission.
    var usesCapturedImage: Bool = true

    /// Nothing to draw: the overlay can be torn down.
    var isIdentity: Bool {
        foldAngle == 0 && blur == 0 && wash == 0 && cornerRadius == 0
            && brightness == 1 && vignette == 0
            && edgeOcclusion == 0 && creaseHighlight == 0 && mask == .none
            && scale == .one && opacity == 1
    }

    /// Fully obscured: no point sampling the desktop any more.
    var isOpaqueBlack: Bool {
        brightness <= 0.001 && opacity >= 0.999
    }
}

/// Environment handed to a preset on every evaluation.
struct AnimationContext: Sendable, Equatable {
    var screenSize: SIMD2<Float>
    var scaleFactor: Double
    var reduceMotion: Bool
    /// User-facing 0...1 strength for the closing direction.
    var closingIntensity: Double
    var openingIntensity: Double
    var capability: HingeCapability
    /// False when screen recording permission is absent or capture failed.
    var captureAvailable: Bool
    /// Per-preset strengths for the ramps the selected preset produces.
    var tuning: PresetTuning
    /// Degrees of travel between the calibrated closed and open positions.
    ///
    /// The Fold preset rotates its panel by the angle the lid has actually swept, so
    /// the on-screen crease keeps pace with the hardware instead of following a curve
    /// of its own.
    var hingeTravelDegrees: Double

    init(
        screenSize: SIMD2<Float> = SIMD2(1512, 982),
        scaleFactor: Double = 2,
        reduceMotion: Bool = false,
        closingIntensity: Double = 1,
        openingIntensity: Double = 1,
        capability: HingeCapability = .continuousAngle,
        captureAvailable: Bool = true,
        hingeTravelDegrees: Double = 95,
        tuning: PresetTuning = .default
    ) {
        self.screenSize = screenSize
        self.scaleFactor = scaleFactor
        self.reduceMotion = reduceMotion
        self.closingIntensity = closingIntensity
        self.openingIntensity = openingIntensity
        self.capability = capability
        self.captureAvailable = captureAvailable
        self.hingeTravelDegrees = hingeTravelDegrees
        self.tuning = tuning
    }

    var aspect: Double {
        Double(screenSize.x / max(screenSize.y, 1))
    }

    /// The intensity that applies to the direction the lid is currently travelling.
    func intensity(for direction: HingeDirection) -> Double {
        direction == .opening ? openingIntensity : closingIntensity
    }
}
