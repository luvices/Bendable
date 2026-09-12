import Metal
import XCTest
@testable import Bendable

/// Exercises the real Metal pipeline offscreen. Skipped where no GPU is exposed, so a
/// headless CI machine still runs the rest of the suite.
final class PresetRendererTests: XCTestCase {
    private var device: MTLDevice!
    private var renderer: PresetRenderer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device on this machine")
        renderer = PresetRenderer(device: device)
        try XCTSkipIf(renderer == nil, "Metal pipeline unavailable")
    }

    private func makeTarget(width: Int = 96, height: Int = 64) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PresetRenderer.pixelFormat, width: width, height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    /// Returns BGRA bytes for the whole target.
    private func readPixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return bytes
    }

    private func pixel(_ bytes: [UInt8], _ texture: MTLTexture, x: Int, y: Int)
        -> (b: Int, g: Int, r: Int, a: Int) {
        let index = (y * texture.width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }

    /// A flat colour source makes it easy to reason about what the shader produced.
    private func makeSourceImage(gray: UInt8 = 200, width: Int = 128, height: Int = 96) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Components must be given in sRGB: CGColor(gray:) lives in a gamma-2.2 grey
        // space and would be converted on the way into the context.
        let level = CGFloat(gray) / 255
        context.setFillColor(CGColor(srgbRed: level, green: level, blue: level, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func testIdentityFrameReproducesTheSourceImage() throws {
        renderer.setTexture(makeSourceImage(gray: 200))
        XCTAssertTrue(renderer.hasTexture)

        var frame = FrameDescription()
        frame.usesCapturedImage = true
        XCTAssertTrue(frame.isIdentity)

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        for point in [(4, 4), (48, 32), (91, 59)] {
            let sample = pixel(bytes, target, x: point.0, y: point.1)
            XCTAssertEqual(sample.a, 255)
            // sRGB 200 round-trips through an unorm target within rounding.
            XCTAssertEqual(sample.r, 200, accuracy: 3, "at \(point)")
            XCTAssertEqual(sample.g, 200, accuracy: 3, "at \(point)")
        }
    }

    func testFullyClosedFoldRendersOpaqueBlack() throws {
        renderer.setTexture(makeSourceImage(gray: 220))
        let frame = CreasePreset().frame(
            progress: 0, velocity: 0, direction: .closing, context: AnimationContext()
        )
        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        let centre = pixel(bytes, target, x: 48, y: 32)
        XCTAssertEqual(centre.a, 255)
        XCTAssertLessThan(centre.r, 4)
        XCTAssertLessThan(centre.g, 4)
    }

    func testFoldingLeavesOpaqueBackdropWhereThePanelNoLongerReaches() throws {
        renderer.setTexture(makeSourceImage(gray: 240))
        var frame = CreasePreset().frame(
            progress: 0.35, velocity: 0, direction: .closing, context: AnimationContext()
        )
        frame.brightness = 1
        frame.vignette = 0
        frame.edgeOcclusion = 0
        frame.creaseHighlight = 0
        frame.blur = 0

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        // The upper panel has rotated away and no longer reaches the top of the
        // screen, which must show the black backdrop rather than a hole onto the
        // live desktop.
        let top = pixel(bytes, target, x: 48, y: 1)
        XCTAssertEqual(top.a, 255, "The backdrop must stay opaque or the desktop shows through")
        XCTAssertLessThan(top.r, 8)

        // The lower panel does not move at all.
        let bottom = pixel(bytes, target, x: 48, y: target.height - 2)
        XCTAssertGreaterThan(bottom.r, 180)
    }

    func testTheStationaryHalfIsUntouchedByTheFold() throws {
        renderer.setTexture(makeSourceImage(gray: 220))
        var frame = CreasePreset().frame(
            progress: 0.5, velocity: 0, direction: .closing, context: AnimationContext()
        )
        frame.brightness = 1
        frame.vignette = 0
        frame.edgeOcclusion = 0
        frame.creaseHighlight = 0
        frame.blur = 0

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        // Everything below the crease is still the source image, pixel for pixel.
        for y in [target.height - 2, target.height * 3 / 4] {
            let sample = pixel(bytes, target, x: 48, y: y)
            XCTAssertEqual(sample.r, 220, accuracy: 3, "row \(y) moved with the folded panel")
        }
    }

    func testMaskPresetsLeaveTheScreenVisibleThroughTheOpening() throws {
        renderer.clearTexture()
        var frame = FrameDescription()
        frame.usesCapturedImage = false
        frame.brightness = 0
        frame.mask = .shutter(openness: 0.35)

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        // Middle of the screen is inside the opening: fully transparent.
        XCTAssertEqual(pixel(bytes, target, x: 48, y: 32).a, 0)
        // Top and bottom are covered by the bars: opaque black.
        XCTAssertEqual(pixel(bytes, target, x: 48, y: 1).a, 255)
        XCTAssertEqual(pixel(bytes, target, x: 48, y: target.height - 2).a, 255)
    }

    /// The flat grey source used elsewhere cannot tell top from bottom, which is how
    /// a vertical flip in the texture upload survived every other test here.
    func testTheDesktopIsNotFlippedOnItsWayToTheGPU() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        // CoreGraphics puts the origin at the bottom left, so this fills the lower half.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        renderer.setTexture(context.makeImage())

        var frame = FrameDescription()
        frame.usesCapturedImage = true
        let target = try makeTarget(width: 64, height: 64)
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        // Row 0 of the render target is the top of the screen, which must be the dark
        // half, the half CoreGraphics drew at high y.
        XCTAssertLessThan(pixel(bytes, target, x: 32, y: 4).r, 12, "The desktop is upside down")
        XCTAssertGreaterThan(pixel(bytes, target, x: 32, y: 59).r, 240, "The desktop is upside down")
    }

    /// Dimming has to happen in light, not in the encoding.
    ///
    /// Sampling encoded bytes as though they were light and multiplying makes a fade
    /// follow the encoding curve instead of the physical one: the picture lingers as a
    /// grey haze and reaches black by a different route than the black beside it, which
    /// is exactly what a fade against a black background must not do.
    func testFadingHappensInLinearLight() throws {
        // Encoded 188 is very close to half the light of white.
        renderer.setTexture(makeSourceImage(gray: 188))

        var frame = FrameDescription()
        frame.usesCapturedImage = true
        frame.brightness = 0.5

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let sample = pixel(readPixels(target), target, x: 48, y: 32)

        // Half of half the light is a quarter, which encodes to about 137.
        // Multiplying the encoded value instead would have given 94.
        XCTAssertEqual(sample.r, 137, accuracy: 5, "The fade is running in the encoding")
    }

    /// And the far end of that fade has to land on the same black the panel sits on, or
    /// the two do not blend.
    func testAFullFadeReachesTheBackdropsBlack() throws {
        renderer.setTexture(makeSourceImage(gray: 200))

        var frame = FrameDescription()
        frame.usesCapturedImage = true
        frame.brightness = 0

        let target = try makeTarget()
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        let onThePanel = pixel(bytes, target, x: 48, y: 32)
        let onTheBackdrop = pixel(bytes, target, x: 1, y: 1)
        XCTAssertEqual(onThePanel.r, onTheBackdrop.r, "The faded panel is a different black")
        XCTAssertEqual(onThePanel.g, onTheBackdrop.g)
        XCTAssertEqual(onThePanel.b, onTheBackdrop.b)
        XCTAssertEqual(onThePanel.r, 0)
    }

    func testRoundedCornersResolveAgainstTheBackdropRatherThanPunchingHoles() throws {
        renderer.setTexture(makeSourceImage(gray: 230))
        var frame = FrameDescription()
        frame.usesCapturedImage = true
        frame.cornerRadius = 0.3

        let target = try makeTarget(width: 128, height: 128)
        renderer.render(frame, into: target)
        let bytes = readPixels(target)

        let corner = pixel(bytes, target, x: 2, y: 2)
        XCTAssertEqual(corner.a, 255, "A rounded corner must be black, not a hole to the desktop")
        XCTAssertLessThan(corner.r, 8)

        let centre = pixel(bytes, target, x: 64, y: 64)
        XCTAssertEqual(centre.r, 230, accuracy: 3)
    }

    func testBlurRemovesHighFrequencyDetail() throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        // A fine checkerboard: anything left after a heavy blur is a bug.
        for row in 0..<16 {
            for column in 0..<16 {
                let level: CGFloat = (row + column) % 2 == 0 ? 1 : 0
                context.setFillColor(CGColor(srgbRed: level, green: level, blue: level, alpha: 1))
                context.fill(CGRect(x: column * 8, y: row * 8, width: 8, height: 8))
            }
        }
        renderer.setTexture(context.makeImage())

        func spread(blur: Double) throws -> Int {
            var frame = FrameDescription()
            frame.usesCapturedImage = true
            frame.blur = blur
            let target = try makeTarget(width: 128, height: 128)
            renderer.render(frame, into: target)
            let bytes = readPixels(target)
            let samples = stride(from: 8, to: 120, by: 8).map { pixel(bytes, target, x: $0, y: 64).r }
            return (samples.max() ?? 0) - (samples.min() ?? 0)
        }

        XCTAssertGreaterThan(try spread(blur: 0), 200)
        XCTAssertLessThan(try spread(blur: 1), 40)
    }

    func testSunsetRendersWithoutATextureAndEndsAtOpaqueBlack() throws {
        renderer.clearTexture()
        let preset = SunsetHDRPreset()

        let sunset = preset.frame(
            progress: 0.45, velocity: 0, direction: .closing, context: AnimationContext()
        )
        let sunsetTarget = try makeTarget()
        renderer.render(sunset, into: sunsetTarget)
        let sunsetPixel = pixel(readPixels(sunsetTarget), sunsetTarget, x: 48, y: 32)
        XCTAssertEqual(sunsetPixel.a, 255)
        XCTAssertGreaterThan(sunsetPixel.r + sunsetPixel.g + sunsetPixel.b, 30)

        let closed = preset.frame(
            progress: 0, velocity: 0, direction: .closing, context: AnimationContext()
        )
        let closedTarget = try makeTarget()
        renderer.render(closed, into: closedTarget)
        let closedPixel = pixel(readPixels(closedTarget), closedTarget, x: 48, y: 32)
        XCTAssertEqual(closedPixel.a, 255)
        XCTAssertLessThan(closedPixel.r, 8)
        XCTAssertLessThan(closedPixel.g, 8)
        XCTAssertLessThan(closedPixel.b, 8)
    }

    func testRenderUniformStrideStaysInStepWithMetal() {
        XCTAssertEqual(MemoryLayout<RenderUniforms>.stride, 128)
    }
}
