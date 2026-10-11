// Draws textier's app icon, direction A of the icon designs ("Marked lines": lines
// of text with colored Pattern pills), at every size an .icns holds, into the
// iconset folder given as the first argument. scripts/make-app-icon.sh runs it.
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha
    )
}

/// The design's 100-unit square, y down, scaled to `pixels`.
func draw(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 100
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }
    func fill(_ path: CGPath, _ fill: CGColor) {
        context.addPath(path)
        context.setFillColor(fill)
        context.fillPath()
    }
    func stroke(_ path: CGPath, _ stroke: CGColor, _ width: CGFloat) {
        context.addPath(path)
        context.setStrokeColor(stroke)
        context.setLineWidth(width)
        context.strokePath()
    }

    // The tile: its drop shadow, a white-to-grey fill, a bright inner edge.
    fill(rounded(10, 11.4, 80, 80, 18), color(0x141828, 0.16))
    let tile = rounded(10, 10, 80, 80, 18)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0xffffff), color(0xe4e6ee)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 50, y: 10), end: CGPoint(x: 50, y: 90), options: [])
    context.restoreGState()
    stroke(rounded(10.4, 10.4, 79.2, 79.2, 17.6), color(0xffffff, 0.95), 0.7)

    // Four lines of text: words as grey bars, Matches as pills in Pattern colors,
    // the third line's ringed as the selected one.
    let word = color(0xc3c6d1)
    fill(rounded(22, 23.5, 23, 9, 3), color(0x6e56cf))
    fill(rounded(48, 25.75, 11, 4.5, 2.25), word)
    fill(rounded(62, 23.5, 16, 9, 3), color(0xe5484d))
    fill(rounded(22, 39.75, 9, 4.5, 2.25), word)
    fill(rounded(34, 37.5, 30, 9, 3), color(0x46a758))
    fill(rounded(67, 39.75, 11, 4.5, 2.25), word)
    fill(rounded(22, 51.5, 38, 9, 3), color(0xffc53d))
    stroke(rounded(22.65, 52.15, 36.7, 7.7, 2.5), color(0xab6400), 1.3)
    fill(rounded(63, 53.75, 15, 4.5, 2.25), word)
    fill(rounded(22, 67.75, 15, 4.5, 2.25), word)
    fill(rounded(40, 65.5, 22, 9, 3), color(0x0090ff))

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try draw(pixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(pixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
