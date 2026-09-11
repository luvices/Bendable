import Foundation
import simd

/// Mirrors `Uniforms` in Shaders.metal. Field order and types must match.
struct RenderUniforms {
    var scale: SIMD2<Float> = .one
    var translate: SIMD2<Float> = .zero
    var foldAngle: Float = 0
    var foldPosition: Float = 0.5
    var perspective: Float = 0
    var curvature: Float = 0
    var creaseHighlight: Float = 0
    var aspect: Float = 1
    var blur: Float = 0
    var blurGradient: Float = 0
    var wash: Float = 0
    var cornerRadius: Float = 0
    var brightness: Float = 1
    var opacity: Float = 1
    var vignette: Float = 0
    var edgeOcclusion: Float = 0
    var maskOpenness: Float = 1
    var maskKind: UInt32 = 0
    var blades: UInt32 = 0
    var useTexture: UInt32 = 0
    var maxLOD: Float = 0

    init() {}

    init(frame: FrameDescription, aspect: Double, hasTexture: Bool, maxLOD: Float) {
        scale = frame.scale
        translate = frame.translate
        foldAngle = Float(frame.foldAngle)
        foldPosition = Float(clamp(frame.foldPosition, 0, 1))
        perspective = Float(frame.perspective)
        curvature = Float(frame.curvature)
        creaseHighlight = Float(clamp(frame.creaseHighlight, 0, 1))
        self.aspect = Float(aspect)
        blur = Float(clamp(frame.blur, 0, 1))
        blurGradient = Float(clamp(frame.blurGradient, 0, 1))
        wash = Float(clamp(frame.wash, 0, 1))
        cornerRadius = Float(clamp(frame.cornerRadius, 0, 1))
        brightness = Float(max(frame.brightness, 0))
        opacity = Float(clamp(frame.opacity, 0, 1))
        vignette = Float(clamp(frame.vignette, 0, 1))
        edgeOcclusion = Float(clamp(frame.edgeOcclusion, 0, 1))
        useTexture = (frame.usesCapturedImage && hasTexture) ? 1 : 0
        self.maxLOD = maxLOD

        switch frame.mask {
        case .none:
            maskKind = 0
        case let .aperture(blades, openness):
            maskKind = 1
            self.blades = UInt32(clamp(blades, 3, 16))
            maskOpenness = Float(clamp(openness, 0, 1))
        case let .shutter(openness):
            maskKind = 2
            maskOpenness = Float(clamp(openness, 0, 1))
        case let .blinds(slats, openness):
            maskKind = 3
            // Shares the iris blade count. Both answer "how many pieces is the mask
            // made of", and no frame carries two kinds of mask at once.
            self.blades = UInt32(clamp(slats, 2, 24))
            maskOpenness = Float(clamp(openness, 0, 1))
        }
    }

    /// Background behind the folded panel. Premultiplied, so black at the frame's alpha.
    static func clearColor(for frame: FrameDescription, hasTexture: Bool) -> (Double, Double, Double, Double) {
        let opaqueBackdrop = frame.usesCapturedImage && hasTexture
        return (0, 0, 0, opaqueBackdrop ? clamp(frame.opacity, 0, 1) : 0)
    }
}
