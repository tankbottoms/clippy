import AppKit
import Foundation

// Generate Clippy app icon: scissors SVG on dark rounded-rect background
// Uses dual-render alpha extraction (white bg + black bg) for clean transparency
// Usage: GenIcon <output-iconset-dir> <svg-path>

guard CommandLine.arguments.count > 2 else {
    fputs("Usage: GenIcon <output-iconset-dir> <svg-path>\n", stderr)
    exit(1)
}

let iconsetDir = CommandLine.arguments[1]
let svgPath = CommandLine.arguments[2]

guard FileManager.default.fileExists(atPath: svgPath),
      let svgData = FileManager.default.contents(atPath: svgPath),
      let svgImage = NSImage(data: svgData) else {
    fputs("Failed to load SVG: \(svgPath)\n", stderr)
    exit(1)
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

/// Render SVG at given size onto a solid background color, return raw pixel data
func renderOnBackground(width: Int, height: Int, bgR: UInt8, bgG: UInt8, bgB: UInt8) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * 4

    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(
        red: CGFloat(bgR) / 255.0,
        green: CGFloat(bgG) / 255.0,
        blue: CGFloat(bgB) / 255.0,
        alpha: 1.0
    ))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let svgW = svgImage.size.width
    let svgH = svgImage.size.height
    let scale = min(CGFloat(width) / svgW, CGFloat(height) / svgH)
    let drawW = svgW * scale
    let drawH = svgH * scale
    let drawX = (CGFloat(width) - drawW) / 2.0
    let drawY = (CGFloat(height) - drawH) / 2.0

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    svgImage.draw(
        in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
        from: .zero, operation: .sourceOver, fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = ctx.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    return (ctx, pixels)
}

/// Dual-render alpha extraction: render on white and black, compute true RGBA
func renderSVGTransparent(width: Int, height: Int) -> CGImage? {
    guard let (_, whitePixels) = renderOnBackground(width: width, height: height, bgR: 255, bgG: 255, bgB: 255),
          let (_, blackPixels) = renderOnBackground(width: width, height: height, bgR: 0, bgG: 0, bgB: 0) else {
        return nil
    }

    let bytesPerRow = width * 4

    // For each pixel:
    // On white: Cw = alpha * C + (1 - alpha) * 255
    // On black: Cb = alpha * C
    // Therefore: alpha = 1 - (Cw - Cb) / 255  (using any channel, average for stability)
    // And: C = Cb / alpha

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let outCtx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    guard let outData = outCtx.data else { return nil }
    let outPixels = outData.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

    for y in 0..<height {
        for x in 0..<width {
            let i = (y * bytesPerRow) + (x * 4)

            let wr = Int(whitePixels[i])
            let wg = Int(whitePixels[i + 1])
            let wb = Int(whitePixels[i + 2])

            let br = Int(blackPixels[i])
            let bg = Int(blackPixels[i + 1])
            let bb = Int(blackPixels[i + 2])

            // Average the alpha estimate across channels for stability
            let diffR = wr - br
            let diffG = wg - bg
            let diffB = wb - bb
            let avgDiff = (diffR + diffG + diffB) / 3

            let alpha = 255 - avgDiff

            if alpha <= 2 {
                // Fully transparent
                outPixels[i] = 0
                outPixels[i + 1] = 0
                outPixels[i + 2] = 0
                outPixels[i + 3] = 0
            } else {
                // Recover original color: C = Cb / alpha (un-premultiply from black render)
                let a = CGFloat(alpha) / 255.0
                let r = min(255, Int(CGFloat(br) / a))
                let g = min(255, Int(CGFloat(bg) / a))
                let b = min(255, Int(CGFloat(bb) / a))

                // Store as premultiplied alpha
                outPixels[i]     = UInt8(r * alpha / 255)
                outPixels[i + 1] = UInt8(g * alpha / 255)
                outPixels[i + 2] = UInt8(b * alpha / 255)
                outPixels[i + 3] = UInt8(alpha)
            }
        }
    }

    return outCtx.makeImage()
}

func renderIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: dark rounded rect with gradient
    let corner = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.12, green: 0.11, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.08, green: 0.07, blue: 0.16, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0])!

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Subtle inner border
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
    ctx.setLineWidth(s * 0.015)
    ctx.strokePath()
    ctx.restoreGState()

    // Draw scissors with clean transparency
    let padding = s * 0.15
    let innerSize = Int(s - padding * 2)

    if let scissorsCG = renderSVGTransparent(width: innerSize, height: innerSize) {
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        ctx.draw(scissorsCG, in: CGRect(x: padding, y: padding, width: CGFloat(innerSize), height: CGFloat(innerSize)))
        ctx.restoreGState()
    }

    img.unlockFocus()
    return img
}

try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let img = renderIcon(size: entry.px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        exit(1)
    }
    let path = (iconsetDir as NSString).appendingPathComponent("\(entry.name).png")
    try png.write(to: URL(fileURLWithPath: path))
}

print("Generated \(sizes.count) icons in \(iconsetDir)")
