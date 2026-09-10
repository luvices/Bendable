import CoreGraphics
import Foundation
import Metal

enum MetalTextureLoader {
    /// Copies a rendered target back into a `CGImage`. Used by the thumbnails and by
    /// the debug contact sheet, both of which draw offscreen.
    static func makeImage(from texture: MTLTexture) -> CGImage? {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// A shared render target, since every offscreen consumer wants the same size.
    static func makeRenderTarget(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PresetRenderer.pixelFormat, width: width, height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    /// Uploads a captured desktop frame with a full mip chain.
    ///
    /// Defocus is done by sampling an explicit mip level rather than by running a
    /// separate blur pass, so the whole effect stays one draw call.
    /// Off the main thread: this draws several million pixels through CoreGraphics and
    /// then waits on the GPU, and it runs at the moment the lid starts moving, exactly
    /// when the main thread has frames to draw.
    static func makeMipmappedTexture(
        from image: CGImage, device: MTLDevice, queue: MTLCommandQueue
    ) async -> MTLTexture? {
        await withCheckedContinuation { continuation in
            uploadQueue.async {
                continuation.resume(returning: makeMipmappedTextureSynchronously(
                    from: image, device: device, queue: queue
                ))
            }
        }
    }

    private static let uploadQueue = DispatchQueue(
        label: "com.bendable.texture-upload", qos: .userInitiated
    )

    static func makeMipmappedTextureSynchronously(from image: CGImage, device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PresetRenderer.pixelFormat, width: width, height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = width * 4
        guard let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: staging.contents(), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        // A bitmap context stores its first row at the top of the image, which is the
        // same order Metal samples in. No flip.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { return nil }

        blit.copy(
            from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow,
            sourceBytesPerImage: bytesPerRow * height,
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }
}
