import AppKit
import Foundation

// Generate Clippy app icon: SF Symbol scissors on a dark rounded-rect background
// Usage: GenIcon <output-iconset-dir>

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: GenIcon <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetDir = CommandLine.arguments[1]

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

func renderIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: dark rounded rect with subtle gradient
    let corner = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Gradient from dark indigo to darker
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

    // Draw scissors using SF Symbol
    let symbolSize = s * 0.52
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)

    if let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {

        let tintColor = NSColor(red: 0.92, green: 0.90, blue: 0.98, alpha: 1.0)
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        tintColor.set()
        let imageRect = NSRect(origin: .zero, size: tinted.size)
        imageRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let symbolW = tinted.size.width
        let symbolH = tinted.size.height
        let drawX = (s - symbolW) / 2.0
        let drawY = (s - symbolH) / 2.0

        tinted.draw(
            in: NSRect(x: drawX, y: drawY, width: symbolW, height: symbolH),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    } else {
        // Fallback: draw scissors with bezier paths
        drawScissorsPaths(ctx: ctx, size: s)
    }

    img.unlockFocus()
    return img
}

func drawScissorsPaths(ctx: CGContext, size s: CGFloat) {
    let color = CGColor(red: 0.92, green: 0.90, blue: 0.98, alpha: 1.0)
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineWidth(s * 0.035)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let cx = s / 2.0
    let cy = s / 2.0

    // Two circular finger holes (bottom)
    let holeRadius = s * 0.09
    let holeSpread = s * 0.14
    let holeY = cy - s * 0.16

    // Left hole
    ctx.strokeEllipse(in: CGRect(
        x: cx - holeSpread - holeRadius,
        y: holeY - holeRadius,
        width: holeRadius * 2,
        height: holeRadius * 2
    ))
    // Right hole
    ctx.strokeEllipse(in: CGRect(
        x: cx + holeSpread - holeRadius,
        y: holeY - holeRadius,
        width: holeRadius * 2,
        height: holeRadius * 2
    ))

    // Blades: two lines crossing from holes to top
    let bladeTopY = cy + s * 0.22
    let bladeTipSpread = s * 0.06

    // Left blade (from right hole to top-left)
    ctx.move(to: CGPoint(x: cx + holeSpread, y: holeY + holeRadius))
    ctx.addLine(to: CGPoint(x: cx - bladeTipSpread, y: bladeTopY))
    ctx.strokePath()

    // Right blade (from left hole to top-right)
    ctx.move(to: CGPoint(x: cx - holeSpread, y: holeY + holeRadius))
    ctx.addLine(to: CGPoint(x: cx + bladeTipSpread, y: bladeTopY))
    ctx.strokePath()
}

// Create iconset directory
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
