// Generates the AgentsUsageWatch app icon from code (CoreGraphics only).
// Usage: swift Tools/make-icon.swift <out-dir> [--preview <preview.png>]
//   <out-dir> receives icon_16x16.png ... icon_512x512@2x.png and Contents.json
//   (point it at App/Assets.xcassets/AppIcon.appiconset).
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// macOS icon body: superellipse (n≈5) approximating Apple's continuous-corner squircle.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5, steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// Draws the icon in a 1024×1024 coordinate space (y up). Same mark as AgentsTrack's icon.svg (flat #4f46e5
/// tile, prompt chevron, caret), except the caret is a usage meter: a dim track with a partial fill.
func drawIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x4F46E5)); ctx.fillPath()
    ctx.restoreGState()

    // Map the 32×32 svg viewBox onto the body (svg y grows downwards).
    let u = body.width / 32
    func svg(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * u, y: body.maxY - y * u) }
    ctx.setLineWidth(2.6 * u); ctx.setLineCap(.round); ctx.setLineJoin(.round)

    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.move(to: svg(9, 11)); ctx.addLine(to: svg(14, 16)); ctx.addLine(to: svg(9, 21)); ctx.strokePath()

    ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
    ctx.move(to: svg(17, 21)); ctx.addLine(to: svg(24, 21)); ctx.strokePath()
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.move(to: svg(17, 21)); ctx.addLine(to: svg(21, 21)); ctx.strokePath()
}

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    drawIcon(ctx)
    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, _ url: URL) {
    let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: swift make-icon.swift <out-dir> [--preview <file.png>]"); exit(1) }
let out = URL(fileURLWithPath: args[1])
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(pt * scale), out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) PNGs + Contents.json to \(out.path)")

// Optional preview: 1024, 128, 32 (actual) and 32 magnified ×8, on light and dark rows.
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    let sizes = [1024, 128, 32], gap = 48, zoom = 256
    let w = gap + sizes.reduce(0) { $0 + $1 + gap } + zoom + gap, rowH = 1024 + 2 * gap
    let ctx = CGContext(data: nil, width: w, height: rowH * 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, bgc) in [rgb(0xF2F2F7), rgb(0x1C1C1E)].enumerated() {
        let y0 = (1 - row) * rowH
        ctx.setFillColor(bgc); ctx.fill(CGRect(x: 0, y: y0, width: w, height: rowH))
        var x = gap
        for s in sizes {
            ctx.interpolationQuality = .high
            ctx.draw(render(s), in: CGRect(x: x, y: y0 + (rowH - s) / 2, width: s, height: s))
            x += s + gap
        }
        ctx.interpolationQuality = .none // nearest-neighbour: shows the real 32 px pixels
        ctx.draw(render(32), in: CGRect(x: x, y: y0 + (rowH - zoom) / 2, width: zoom, height: zoom))
    }
    writePNG(ctx.makeImage()!, URL(fileURLWithPath: args[i + 1]))
    print("wrote preview \(args[i + 1])")
}
