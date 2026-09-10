import Foundation
import Metal
import QuartzCore
import simd

/// Draws a `FrameDescription` into a `CAMetalLayer`.
///
/// One pipeline covers every preset: presets differ only in the uniforms they
/// produce, so adding a preset never touches this file.
final class PresetRenderer {
    /// Every surface in the overlay uses this.
    ///
    /// The `_srgb` suffix is what makes the fade correct. Without it the shader samples
    /// encoded bytes as though they were light, and multiplying those by a brightness
    /// is not a dimming: it follows the encoding curve instead of the physical one, so
    /// the picture lingers as a grey haze and arrives at black by a different route than
    /// the black it is sitting on. Which is precisely what a fade against a black
    /// background must not do. With this the GPU decodes on read and re-encodes on
    /// write, so the arithmetic in between is in light, and blending and mipmapping are
    /// too.
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// Cells per axis in the panel mesh. Enough for the cylindrical bow to read as a
    /// smooth curve; the vertex count is negligible next to a single full-screen pass.
    private static let gridResolution = 48

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let gridBuffer: MTLBuffer
    private let gridVertexCount: Int

    private var texture: MTLTexture?
    private var maxLOD: Float = 0

    var hasTexture: Bool { texture != nil }

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device,
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: BundleToken.self)),
              let vertexFunction = library.makeFunction(name: "foldVertex"),
              let fragmentFunction = library.makeFunction(name: "foldFragment")
        else {
            Log.animation.error("Metal renderer unavailable")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        // Premultiplied source-over. The pass clears to the backdrop first and the
        // panel blends onto it, which is what lets rounded corners and the panel's
        // own edges resolve against black instead of punching holes in the overlay.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        else {
            Log.animation.error("Metal pipeline creation failed")
            return nil
        }

        let grid = Self.makeGrid(resolution: Self.gridResolution)
        guard let gridBuffer = device.makeBuffer(
            bytes: grid, length: MemoryLayout<SIMD2<Float>>.stride * grid.count, options: .storageModeShared
        ) else { return nil }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.sampler = sampler
        self.gridBuffer = gridBuffer
        self.gridVertexCount = grid.count
    }

    /// The pieces needed to build a texture, so callers can do the upload off the
    /// renderer's own isolation and hand back only the finished texture.
    var uploadContext: (device: MTLDevice, queue: MTLCommandQueue) {
        (device, commandQueue)
    }

    func adopt(_ uploaded: MTLTexture) {
        apply(uploaded)
    }

    func setTexture(_ image: CGImage?) {
        guard let image else {
            texture = nil
            maxLOD = 0
            return
        }
        guard let uploaded = MetalTextureLoader.makeMipmappedTextureSynchronously(
            from: image, device: device, queue: commandQueue
        ) else { return }
        apply(uploaded)
    }

    private func apply(_ uploaded: MTLTexture) {
        texture = uploaded
        // The last few mip levels are a handful of pixels, and sampling them turns full
        // blur into flat colour. Stopping short leaves the broad shapes of the desktop
        // legible, which is what a lens actually does.
        maxLOD = max(Float(uploaded.mipmapLevelCount - 1) - 3, 0)
    }

    func clearTexture() {
        setTexture(nil)
    }

    func render(_ frame: FrameDescription, in layer: CAMetalLayer) {
        guard layer.drawableSize.width > 0, layer.drawableSize.height > 0,
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        encode(frame, into: drawable.texture, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Offscreen variant, used by the render tests.
    func render(_ frame: FrameDescription, into target: MTLTexture) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encode(frame, into: target, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func encode(_ frame: FrameDescription, into target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let clear = RenderUniforms.clearColor(for: frame, hasTexture: hasTexture)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: clear.0, green: clear.1, blue: clear.2, alpha: clear.3
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let aspect = Double(target.width) / Double(max(target.height, 1))
        var uniforms = RenderUniforms(frame: frame, aspect: aspect, hasTexture: hasTexture, maxLOD: maxLOD)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        if let texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertexCount)
        encoder.endEncoding()
    }

    private static func makeGrid(resolution: Int) -> [SIMD2<Float>] {
        var vertices: [SIMD2<Float>] = []
        vertices.reserveCapacity(resolution * resolution * 6)
        let step = 1 / Float(resolution)
        for row in 0..<resolution {
            for column in 0..<resolution {
                let x0 = Float(column) * step, x1 = x0 + step
                let y0 = Float(row) * step, y1 = y0 + step
                vertices.append(SIMD2(x0, y0))
                vertices.append(SIMD2(x1, y0))
                vertices.append(SIMD2(x0, y1))
                vertices.append(SIMD2(x1, y0))
                vertices.append(SIMD2(x1, y1))
                vertices.append(SIMD2(x0, y1))
            }
        }
        return vertices
    }
}

private final class BundleToken {}
