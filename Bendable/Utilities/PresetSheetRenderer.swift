#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Renders a preset across its whole travel into one PNG.
///
/// Reachable from `Bendable --render-sheet <preset> <output.png>` in Debug builds, so
/// changes to the geometry can be checked without opening and closing a laptop, and
/// without a second copy of the preset maths.
enum PresetSheetRenderer {
    private static let tileSize = (width: 440, height: 275)
    private static let columns = 4
    private static let progresses: [Double] = [1.0, 0.88, 0.76, 0.64, 0.52, 0.40, 0.26, 0.10]

    /// Parses the debug arguments and renders, returning true if it handled them.
    @MainActor
    static func handleCommandLine(_ arguments: [String] = CommandLine.arguments) -> Bool {
        if let flagIndex = arguments.firstIndex(of: "--render-ui") {
            let remaining = arguments.dropFirst(flagIndex + 1)
            guard let output = remaining.first else {
                FileHandle.standardError.write(
                    Data("usage: Bendable --render-ui <output.png> [style|hinge|status]\n".utf8)
                )
                return true
            }
            let tab = remaining.dropFirst().first.flatMap(PopoverTab.init(rawValue:)) ?? .style
            do {
                try PopoverSnapshot.render(to: URL(fileURLWithPath: output), tab: tab)
                print("Wrote \(output)")
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
            }
            return true
        }

        guard let flagIndex = arguments.firstIndex(of: "--render-sheet") else { return false }
        let remaining = arguments.dropFirst(flagIndex + 1)
        guard let presetID = remaining.first, let output = remaining.dropFirst().first else {
            FileHandle.standardError.write(
                Data("usage: Bendable --render-sheet <preset-id> <output.png>\n".utf8)
            )
            return true
        }
        do {
            try render(presetID: presetID, to: URL(fileURLWithPath: output))
            print("Wrote \(output)")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
        }
        return true
    }

    enum RenderError: Error {
        case metalUnavailable
        case imageCreationFailed
    }

    static func render(presetID: String, to url: URL) throws {
        guard let renderer = PresetRenderer() else { throw RenderError.metalUnavailable }
        let preset = AnimationPresetCatalog.preset(id: presetID)
        renderer.setTexture(PreviewImage.placeholder())

        let rows = (progresses.count + columns - 1) / columns
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let sheet = CGContext(
                data: nil, width: tileSize.width * columns, height: tileSize.height * rows,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw RenderError.imageCreationFailed }

        var context = AnimationContext()
        context.hingeTravelDegrees = HingeCalibration.defaultStartAngle
        let backdrop = PreviewImage.placeholder()

        for (index, progress) in progresses.enumerated() {
            let frame = preset.frame(
                progress: progress, velocity: 0, direction: .closing, context: context
            )
            guard let tile = renderTile(frame, renderer: renderer, colorSpace: colorSpace) else { continue }
            let column = index % columns
            let row = index / columns
            let rect = CGRect(
                x: column * tileSize.width, y: (rows - 1 - row) * tileSize.height,
                width: tileSize.width, height: tileSize.height
            )
            // Presets that mask instead of redrawing are transparent where the real
            // desktop shows through, so the tile has to be composited over one.
            if let backdrop {
                sheet.draw(backdrop, in: rect)
            }
            sheet.draw(tile, in: rect)
        }

        guard let image = sheet.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else { throw RenderError.imageCreationFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.imageCreationFailed }
    }

    private static func renderTile(
        _ frame: FrameDescription, renderer: PresetRenderer, colorSpace: CGColorSpace
    ) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PresetRenderer.pixelFormat, width: tileSize.width,
            height: tileSize.height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        renderer.render(frame, into: target)

        let bytesPerRow = tileSize.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * tileSize.height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            target.getBytes(
                base, bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, tileSize.width, tileSize.height), mipmapLevel: 0
            )
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: tileSize.width, height: tileSize.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
#endif
