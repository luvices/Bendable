import CoreGraphics
import Metal
import SwiftUI

/// Renders each preset to a small still so the style picker shows what a style
/// actually does rather than naming it.
///
/// Thumbnails go through the real preset and the real shader, so they cannot drift
/// away from what the lid will produce. Results are cached on preset plus tuning, and
/// only the selected preset's tuning changes, so dragging a slider re-renders one
/// image rather than the whole grid.
@MainActor
final class PresetThumbnailRenderer {
    static let shared = PresetThumbnailRenderer()

    /// Fallback for a preset that does not name its own sample point: early enough to
    /// leave the desktop legible, deep enough that the turning presets are visibly
    /// turning.
    static let previewProgress = 0.68
    private static let size = (width: 300, height: 190)

    private struct Key: Hashable {
        let presetID: String
        let tuning: PresetTuning
        let progress: Double
    }

    private let renderer: PresetRenderer?
    private let device: MTLDevice?
    private var target: MTLTexture?
    private var backdrop: CGImage?
    private var cache: [Key: CGImage] = [:]

    private init() {
        device = MTLCreateSystemDefaultDevice()
        renderer = PresetRenderer(device: device)
        backdrop = PreviewImage.placeholder()
        renderer?.setTexture(backdrop)
    }

    func image(
        for preset: any AnimationPreset, tuning: PresetTuning, progress: Double? = nil
    ) -> CGImage? {
        let progress = progress ?? preset.thumbnailProgress
        let key = Key(presetID: preset.id, tuning: tuning, progress: progress)
        if let cached = cache[key] { return cached }

        guard let renderer, let device else { return nil }
        if target == nil {
            target = MetalTextureLoader.makeRenderTarget(
                device: device, width: Self.size.width, height: Self.size.height
            )
        }
        guard let target else { return nil }

        var context = AnimationContext()
        context.tuning = tuning
        context.hingeTravelDegrees = 100
        context.screenSize = SIMD2(Float(Self.size.width), Float(Self.size.height))
        let frame = preset.frame(
            progress: progress, velocity: 0, direction: .closing, context: context
        )
        renderer.render(frame, into: target)
        guard let rendered = MetalTextureLoader.makeImage(from: target) else { return nil }

        // Presets that mask rather than redraw are transparent where the desktop shows
        // through, so the thumbnail has to be composited over one.
        let composited = compositeOverBackdrop(rendered) ?? rendered
        // The cache is bounded by how many distinct tunings a person drags through in
        // one sitting, which is small, but it is not worth growing without limit.
        if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = composited
        return composited
    }

    private func compositeOverBackdrop(_ image: CGImage) -> CGImage? {
        guard let backdrop, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(backdrop, in: rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

struct PresetThumbnail: View {
    let preset: any AnimationPreset
    let tuning: PresetTuning
    var height: CGFloat = 78

    var body: some View {
        ZStack {
            if let image = PresetThumbnailRenderer.shared.image(for: preset, tuning: tuning) {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(3)
    }
}
