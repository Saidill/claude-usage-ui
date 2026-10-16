// Draws the app icon (a black glass tile with a silver ring, like the menu bar icon)
// and writes an .iconset folder for `iconutil`. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024-point canvas; smaller sizes are scaled from it.
func draw(in ctx: CGContext) {
    // Tile: Apple's icon grid leaves a 100pt margin around an 824pt rounded square.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x0B0B0D).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Glass: a soft sheen from the top, clipped to the tile.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sheen = CGGradient(colorsSpace: space, colors: [color(0x2A2A30).cgColor, color(0x0B0B0D).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    ctx.restoreGState()

    // Rim of light along the tile edge.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setLineWidth(4)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rim = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.35).cgColor, color(0xFFFFFF, 0.04).cgColor] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    ctx.restoreGState()

    // Ring: a faint full track, then a silver arc about two-thirds of the way round.
    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 230
    ctx.setLineCap(.round)
    ctx.setLineWidth(64)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.setStrokeColor(color(0xFFFFFF, 0.08).cgColor)
    ctx.strokePath()

    ctx.saveGState()
    let start = CGFloat.pi / 2
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - .pi * 2 * 0.68, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let silver = CGGradient(colorsSpace: space, colors: [color(0xFAFAFC).cgColor, color(0x9EA3AB).cgColor] as CFArray,
                            locations: [0, 1])!
    ctx.drawLinearGradient(silver, start: CGPoint(x: 512, y: 512 + radius + 40), end: CGPoint(x: 512, y: 512 - radius - 40),
                           options: [])
    ctx.restoreGState()

    // Small dot in the middle, like the menu bar icon while Claude is working.
    ctx.setFillColor(color(0xD4D7DD).cgColor)
    ctx.fillEllipse(in: CGRect(x: 512 - 34, y: 512 - 34, width: 68, height: 68))
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(in: ctx)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
