// Assembles the README demo from the frames the DemoFrames app test captures:
// `swift scripts/make-demo.swift <frames folder> <output folder>` writes demo.mp4
// (1600×1000, 30 fps) and demo.gif (smaller, holds as single frames). Run through
// scripts/make-demo.sh.
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let frames = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let iconURL = URL(fileURLWithPath: "docs/assets/icon.png")

let width = 1600, height = 1000
let fps = 30
/// How long one shot fades into the next.
let fade = 0.4

// MARK: The script

enum Layout {
    /// The title or end card.
    case card(title: String, tagline: String, footer: String)
    /// A popover frame on the right, under a stand-in menu bar, the caption left.
    case popover(String)
    /// A window frame under the caption.
    case window(String)
}

struct Shot {
    var layout: Layout
    var caption = ""
    var detail = ""
    var seconds: Double
}

let shots = [
    Shot(layout: .card(title: "textier", tagline: "Select text anywhere. Press ⌃⌥T.",
                       footer: "Timestamps, JSON, URLs and file paths become things you can act on."), seconds: 2.6),
    Shot(layout: .popover("popover-1-list"), caption: "Select. Press ⌃⌥T.",
         detail: "Every timestamp, JSON blob, URL and path in your selection, found and listed.", seconds: 3.0),
    Shot(layout: .popover("popover-2-datetime"), caption: "Open any Match in place",
         detail: "A datetime shows its local time, UTC, epoch and how long ago.", seconds: 2.8),
    Shot(layout: .popover("popover-3-json"), caption: "JSON, beautified",
         detail: "Right in the popover. Copy it, pop it out, or open the tree.", seconds: 2.6),
    Shot(layout: .window("panel-1-input"), caption: "The Panel, for a whole log",
         detail: "Paste or type: Matches light up as you go.", seconds: 0.9),
    Shot(layout: .window("panel-2-input"), caption: "The Panel, for a whole log",
         detail: "Paste or type: Matches light up as you go.", seconds: 0.9),
    Shot(layout: .window("panel-3-input"), caption: "The Panel, for a whole log",
         detail: "Paste or type: Matches light up as you go.", seconds: 1.8),
    Shot(layout: .window("panel-4-datetime"), caption: "Grouped by Pattern, parsed on the spot",
         detail: "Datetimes, JSON, URLs, file paths, log levels, and Patterns of your own.", seconds: 2.6),
    Shot(layout: .window("panel-6-jsonpath"), caption: "Query JSON with JSONPath",
         detail: "$.items[?@.qty > 1].sku · filters, wildcards, Copy Results.", seconds: 1.0),
    Shot(layout: .window("panel-7-jsonpath"), caption: "Query JSON with JSONPath",
         detail: "$.items[?@.qty > 1].sku · filters, wildcards, Copy Results.", seconds: 2.6),
    Shot(layout: .window("settings-1-pattern"), caption: "Make it yours",
         detail: "Your own regex and Grok Patterns, Color Rules, and a live test box.", seconds: 3.0),
    Shot(layout: .card(title: "textier", tagline: "Native · Private · Open source",
                       footer: "github.com/loco1842/textier"), seconds: 3.2),
]

// MARK: Drawing

let background = [CGColor(srgbRed: 0x2b / 255, green: 0x22 / 255, blue: 0x55 / 255, alpha: 1),
                  CGColor(srgbRed: 0x0e / 255, green: 0x0d / 255, blue: 0x16 / 255, alpha: 1)]
let white = CGColor(gray: 1, alpha: 1)
let dim = CGColor(gray: 1, alpha: 0.62)
let accent = CGColor(srgbRed: 0xb4 / 255, green: 0xa6 / 255, blue: 0xff / 255, alpha: 1)

func load(_ name: String) -> CGImage {
    let url = frames.appendingPathComponent(name + ".png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("No frame \(url.path)") }
    return image
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// A line of text; `x` is its left edge, or its center when `centered`. y is the baseline, from the top.
func text(_ string: String, in ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: CGColor = white, centered: Bool = false, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color)!,
    ]))
    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: centered ? x - lineWidth / 2 : x, y: CGFloat(height) - y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// Words wrapped to `maxWidth`, one baseline every `leading`.
func paragraph(_ string: String, in ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, maxWidth: CGFloat,
               leading: CGFloat, color: CGColor) {
    let font = NSFont.systemFont(ofSize: size)
    var lines: [String] = [], current = ""
    for word in string.split(separator: " ") {
        let candidate = current.isEmpty ? String(word) : current + " " + word
        if (candidate as NSString).size(withAttributes: [.font: font]).width > maxWidth, !current.isEmpty {
            lines.append(current)
            current = String(word)
        } else {
            current = candidate
        }
    }
    lines.append(current)
    for (index, line) in lines.enumerated() {
        text(line, in: ctx, x: x, y: y + CGFloat(index) * leading, size: size, color: color)
    }
}

func fillBackground(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: background as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    // A soft glow behind the content.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(srgbRed: 0.43, green: 0.34, blue: 0.81, alpha: 0.28), CGColor(srgbRed: 0.43, green: 0.34, blue: 0.81, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: width / 2, y: height / 2), startRadius: 0,
                           endCenter: CGPoint(x: width / 2, y: height / 2), endRadius: 760, options: [])
}

/// `image` in `rect` (from the top), with a drop shadow.
func drawShadowed(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
    let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: CGColor(gray: 0, alpha: 0.55))
    ctx.interpolationQuality = .high
    ctx.draw(image, in: flipped)
    ctx.restoreGState()
}

/// Keycaps for a shortcut, centered on x.
func keycaps(_ keys: [String], in ctx: CGContext, centerX: CGFloat, y: CGFloat) {
    let size: CGFloat = 46, gap: CGFloat = 12
    let total = CGFloat(keys.count) * size + CGFloat(keys.count - 1) * gap
    for (index, key) in keys.enumerated() {
        let x = centerX - total / 2 + CGFloat(index) * (size + gap)
        let rect = CGRect(x: x, y: CGFloat(height) - y - size, width: size, height: size)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.1))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        ctx.setLineWidth(1.5)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.strokePath()
        text(key, in: ctx, x: x + size / 2, y: y + 32, size: 24, weight: .medium, centered: true)
    }
}

let icon: CGImage = {
    guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("No \(iconURL.path); run from the repo root") }
    return image
}()

/// textier's menu bar glyph (MenuBarGlyph.swift), 18 pt drawn at `scale`, top-left at origin (from the top).
func glyph(in ctx: CGContext, at origin: CGPoint, scale: CGFloat, color: CGColor) {
    func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        let rect = CGRect(x: origin.x + x * scale, y: CGFloat(height) - origin.y - (y + h) * scale, width: w * scale, height: h * scale)
        return CGPath(roundedRect: rect, cornerWidth: r * scale, cornerHeight: r * scale, transform: nil)
    }
    ctx.setFillColor(color)
    for path in [pill(2, 3, 6.5, 4, 1.4), pill(10.5, 4.3, 5.5, 1.4, 0.7), pill(2, 8.3, 14, 1.4, 0.7), pill(2, 12.3, 3.5, 1.4, 0.7)] {
        ctx.addPath(path)
        ctx.fillPath()
    }
    ctx.setStrokeColor(color)
    ctx.setLineWidth(1.2 * scale)
    ctx.addPath(pill(7.6, 11.1, 8.4, 3.8, 1.3))
    ctx.strokePath()
}

/// The popover, see-through where it is, from its captures over black and over
/// white: a pixel's transparency is how much of the white showed through.
func popoverImage(_ name: String) -> CGImage {
    func pixels(_ image: CGImage) -> [UInt8] {
        let ctx = makeContext(image.width, image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: ctx.bytesPerRow * image.height))
    }
    let black = load(name + "-black"), white = load(name + "-white")
    let w = black.width, h = black.height
    let ctx = makeContext(w, h)
    let onBlack = pixels(black), onWhite = pixels(white)
    let out = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = ctx.bytesPerRow
    precondition(rowBytes == makeContext(w, h).bytesPerRow)
    for row in 0..<h {
        for column in 0..<w {
            let i = row * rowBytes + column * 4
            // BGRA, premultiplied: over black a pixel is its own color times its alpha.
            var alpha = 0
            for channel in 0..<3 {
                alpha = max(alpha, 255 - (Int(onWhite[i + channel]) - Int(onBlack[i + channel])))
            }
            alpha = min(255, max(alpha, Int(onBlack[i]), Int(onBlack[i + 1]), Int(onBlack[i + 2])))
            out[i] = onBlack[i]; out[i + 1] = onBlack[i + 1]; out[i + 2] = onBlack[i + 2]
            out[i + 3] = UInt8(alpha)
        }
    }
    return ctx.makeImage()!
}

func render(_ shot: Shot) -> CGImage {
    let ctx = makeContext(width, height)
    fillBackground(ctx)
    switch shot.layout {
    case let .card(title, tagline, footer):
        let iconSize: CGFloat = 190
        ctx.draw(icon, in: CGRect(x: CGFloat(width) / 2 - iconSize / 2, y: CGFloat(height) - 190 - iconSize, width: iconSize, height: iconSize))
        text(title, in: ctx, x: CGFloat(width) / 2, y: 500, size: 92, weight: .bold, centered: true)
        text(tagline, in: ctx, x: CGFloat(width) / 2, y: 580, size: 38, weight: .semibold, color: accent, centered: true)
        if footer.hasPrefix("github") {
            text(footer, in: ctx, x: CGFloat(width) / 2, y: 680, size: 30, weight: .medium, color: dim, centered: true, mono: true)
        } else {
            keycaps(["⌃", "⌥", "T"], in: ctx, centerX: CGFloat(width) / 2, y: 625)
            text(footer, in: ctx, x: CGFloat(width) / 2, y: 755, size: 28, color: dim, centered: true)
        }
    case let .popover(name):
        // A stand-in menu bar with textier's icon, the popover hanging from it.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.08))
        ctx.fill(CGRect(x: 0, y: CGFloat(height) - 34, width: CGFloat(width), height: 34))
        let image = popoverImage(name)
        let drawHeight: CGFloat = CGFloat(height) - 40
        let drawWidth = drawHeight * CGFloat(image.width) / CGFloat(image.height)
        let rect = CGRect(x: 1180 - drawWidth / 2, y: 22, width: drawWidth, height: drawHeight)
        ctx.draw(image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        let highlight = CGRect(x: 1180 - 20, y: CGFloat(height) - 31, width: 40, height: 28)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.2))
        ctx.addPath(CGPath(roundedRect: highlight, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
        glyph(in: ctx, at: CGPoint(x: 1180 - 13.5, y: 3.5), scale: 1.5, color: white)
        text(shot.caption, in: ctx, x: 110, y: 430, size: 56, weight: .bold)
        paragraph(shot.detail, in: ctx, x: 112, y: 500, size: 28, maxWidth: 640, leading: 40, color: dim)
    case let .window(name):
        let image = load(name)
        text(shot.caption, in: ctx, x: CGFloat(width) / 2, y: 88, size: 50, weight: .bold, centered: true)
        text(shot.detail, in: ctx, x: CGFloat(width) / 2, y: 136, size: 26, color: dim, centered: true)
        let maxW: CGFloat = 1420, maxH: CGFloat = 810
        let scale = min(maxW / CGFloat(image.width), maxH / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        drawShadowed(image, in: CGRect(x: (CGFloat(width) - w) / 2, y: 172, width: w, height: h), ctx)
    }
    return ctx.makeImage()!
}

/// `a` faded into `b` by `t` (0…1).
func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat, width w: Int, height h: Int) -> CGImage {
    let ctx = makeContext(w, h)
    ctx.interpolationQuality = .high
    ctx.draw(a, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setAlpha(t)
    ctx.draw(b, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func scaled(_ image: CGImage, width w: Int, height h: Int) -> CGImage {
    let ctx = makeContext(w, h)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// A smooth start and stop for the fades.
func ease(_ t: Double) -> CGFloat { CGFloat(t * t * (3 - 2 * t)) }

// MARK: Writing

let rendered = shots.map(render)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// The MP4: each shot held, then faded into the next.
func writeMovie() throws {
    let url = output.appendingPathComponent("demo.mp4")
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var frame: Int64 = 0
    func append(_ image: CGImage) {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        while !input.isReadyForMoreMediaData { usleep(1000) }
        adaptor.append(pixels, withPresentationTime: CMTime(value: frame, timescale: CMTimeScale(fps)))
        frame += 1
    }
    for (index, shot) in shots.enumerated() {
        let isLast = index == shots.count - 1
        let hold = Int((shot.seconds - (isLast ? 0 : fade)) * Double(fps))
        for _ in 0..<hold { append(rendered[index]) }
        guard !isLast else { break }
        let steps = Int(fade * Double(fps))
        for step in 1...steps {
            append(blend(rendered[index], rendered[index + 1], ease(Double(step) / Double(steps + 1)), width: width, height: height))
        }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    print("Wrote \(url.path): \(frame) frames")
}

// The GIF: smaller, each hold one frame with a long delay, and a short fade.
func writeGIF() throws {
    let gifWidth = 1200, gifHeight = 750, fadeSteps = 3
    let url = output.appendingPathComponent("demo.gif")
    var images: [(CGImage, Double)] = []
    let small = rendered.map { scaled($0, width: gifWidth, height: gifHeight) }
    for (index, shot) in shots.enumerated() {
        let isLast = index == shots.count - 1
        images.append((small[index], shot.seconds - (isLast ? 0 : fade)))
        guard !isLast else { break }
        for step in 1...fadeSteps {
            images.append((blend(small[index], small[index + 1], ease(Double(step) / Double(fadeSteps + 1)),
                                 width: gifWidth, height: gifHeight), fade / Double(fadeSteps)))
        }
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil)!
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
    ] as CFDictionary)
    for (image, delay) in images {
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("Wrote \(url.path): \(images.count) frames")
}

try writeMovie()
try writeGIF()
