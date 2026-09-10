import CoreGraphics
import Foundation

/// A drawn stand-in for the desktop, used by the preview when screen recording
/// permission is absent. Generated locally; nothing is read from the screen.
enum PreviewImage {
    static func placeholder(size: CGSize = CGSize(width: 1024, height: 640)) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.10, green: 0.13, blue: 0.24, alpha: 1),
                CGColor(red: 0.30, green: 0.18, blue: 0.34, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []
            )
        }

        // A menu bar and a couple of windows give the fold something with structure
        // and straight edges to distort.
        context.setFillColor(CGColor(gray: 0.08, alpha: 0.55))
        context.fill(CGRect(x: 0, y: size.height - 28, width: size.width, height: 28))

        let windows = [
            CGRect(x: size.width * 0.08, y: size.height * 0.18, width: size.width * 0.46, height: size.height * 0.52),
            CGRect(x: size.width * 0.44, y: size.height * 0.30, width: size.width * 0.46, height: size.height * 0.46),
        ]
        for (index, window) in windows.enumerated() {
            context.setFillColor(CGColor(gray: index == 0 ? 0.16 : 0.92, alpha: 0.95))
            context.fill(window)
            context.setFillColor(CGColor(gray: index == 0 ? 0.26 : 0.78, alpha: 1))
            context.fill(CGRect(x: window.minX, y: window.maxY - 24, width: window.width, height: 24))

            context.setFillColor(CGColor(gray: index == 0 ? 0.42 : 0.55, alpha: 1))
            let widths: [CGFloat] = [0.72, 0.55, 0.81, 0.38, 0.64, 0.47, 0.76, 0.29, 0.58, 0.69]
            var lineY = window.maxY - 56
            var line = index * 3
            while lineY > window.minY + 20 {
                let width = window.width * widths[line % widths.count]
                context.fill(CGRect(x: window.minX + 16, y: lineY, width: width, height: 8))
                lineY -= 22
                line += 1
            }
        }

        return context.makeImage()
    }
}
