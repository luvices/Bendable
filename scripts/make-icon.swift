// Draws the app icon. Run through scripts/make-icon.sh, which also cuts the asset
// catalogue sizes.
//
// The icon is the effect, applied to a screen: a display foreshortened into a keystone
// as it tips back, its desktop still deep and readable at the hinge and washed out to
// haze at the receding edge. That is precisely what Fold does, and it gives the icon a
// solid silhouette. A laptop drawn edge-on is two lines and reads as a chevron at any
// size.

import AppKit

let canvas = 1024.0
func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * canvas, y: y * canvas) }
func length(_ value: Double) -> Double { value * canvas }

let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.setAllowsAntialiasing(true)

/// A polygon with rounded corners.
func roundedPolygon(_ points: [CGPoint], radius: Double) -> CGPath {
    let path = CGMutablePath()
    guard points.count > 2 else { return path }
    let start = CGPoint(
        x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2
    )
    path.move(to: start)
    for index in 1...points.count {
        let corner = points[index % points.count]
        let next = points[(index + 1) % points.count]
        path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
    }
    path.closeSubpath()
    return path
}

// MARK: Plate

let inset = length(0.085)
let plate = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
context.saveGState()
context.addPath(CGPath(
    roundedRect: plate, cornerWidth: plate.width * 0.2237, cornerHeight: plate.height * 0.2237,
    transform: nil
))
context.clip()
context.drawLinearGradient(
    CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.157, green: 0.161, blue: 0.184, alpha: 1),
            CGColor(srgbRed: 0.055, green: 0.055, blue: 0.071, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!,
    start: at(0, 1), end: at(0, 0), options: []
)

// MARK: Geometry
//
// The display, tipped back. The top edge is markedly narrower than the bottom: that
// keystone is the whole effect, so the icon states it plainly rather than hinting.

let deckY = 0.296
let deckThickness = 0.052
let screenBottom = deckY + deckThickness / 2
let screenTop = 0.734
let bottomLeft = at(0.232, screenBottom)
let bottomRight = at(0.768, screenBottom)
let topRight = at(0.664, screenTop)
let topLeft = at(0.336, screenTop)
let screen = roundedPolygon(
    [bottomLeft, bottomRight, topRight, topLeft], radius: length(0.032)
)

// MARK: Haze around the receding edge

let haze = at(0.5, screenTop - 0.06)
context.drawRadialGradient(
    CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.898, green: 0.914, blue: 0.965, alpha: 0.30),
            CGColor(srgbRed: 0.831, green: 0.859, blue: 0.945, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!,
    startCenter: haze, startRadius: 0, endCenter: haze, endRadius: length(0.34), options: []
)

// MARK: The display

context.saveGState()
context.addPath(screen)
context.clip()
// Deep and saturated where the panel still faces you, washing to haze as it turns
// away, the same order the preset itself works in.
context.drawLinearGradient(
    CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.180, green: 0.188, blue: 0.404, alpha: 1),
            CGColor(srgbRed: 0.404, green: 0.392, blue: 0.616, alpha: 1),
            CGColor(srgbRed: 0.831, green: 0.831, blue: 0.882, alpha: 1),
            CGColor(srgbRed: 0.973, green: 0.965, blue: 0.949, alpha: 1),
        ] as CFArray,
        locations: [0, 0.34, 0.76, 1]
    )!,
    start: at(0, screenBottom), end: at(0, screenTop), options: []
)
// A little light gathering along the top edge, where the panel is closest to edge on.
context.drawLinearGradient(
    CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!,
    start: at(0, screenTop), end: at(0, screenTop - 0.12), options: []
)
context.restoreGState()

// The bezel, which is what stops the panel dissolving into the plate at the bottom.
context.addPath(screen)
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
context.setLineWidth(length(0.006))
context.strokePath()

// MARK: The deck

let deck = CGMutablePath()
deck.move(to: at(0.205, deckY))
deck.addLine(to: at(0.795, deckY))
let deckPath = deck.copy(
    strokingWithWidth: length(deckThickness), lineCap: .round, lineJoin: .round, miterLimit: 10
)
context.saveGState()
context.addPath(deckPath)
context.clip()
context.drawLinearGradient(
    CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.910, green: 0.925, blue: 0.945, alpha: 1),
            CGColor(srgbRed: 0.573, green: 0.600, blue: 0.655, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!,
    start: at(0, deckY + deckThickness / 2), end: at(0, deckY - deckThickness / 2), options: []
)
context.restoreGState()

context.restoreGState()

// MARK: Write

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(url.path)")
