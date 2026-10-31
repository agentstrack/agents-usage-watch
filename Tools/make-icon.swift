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

func lerp(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let x = a.components!, y = b.components!
    return CGColor(srgbRed: x[0] + (y[0] - x[0]) * t, green: x[1] + (y[1] - x[1]) * t,
                   blue: x[2] + (y[2] - x[2]) * t, alpha: 1)
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

/// Draws the icon in a 1024×1024 coordinate space (y up).
func drawIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1E1B4B)); ctx.fillPath()
    ctx.restoreGState()

    // Body: AgentsTrack indigo (#4f46e5) vertical gradient + soft top glow for depth.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(0x5B54F0), rgb(0x312E81)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 860), endRadius: 560, options: [])
    ctx.restoreGState()
    // Hairline rim so the dark body separates from dark backgrounds.
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(4); ctx.strokePath()

    // Gauge: 270° sweep opening at the bottom.
    let center = CGPoint(x: 512, y: 492), radius: CGFloat = 250, width: CGFloat = 124
    let start: CGFloat = 225, sweep: CGFloat = 270
    let value: CGFloat = 0.70, pace: CGFloat = 0.52
    func angle(_ f: CGFloat) -> CGFloat { (start - sweep * f) * .pi / 180 }
    func point(_ f: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: center.x + r * cos(angle(f)), y: center.y + r * sin(angle(f)))
    }

    ctx.setLineCap(.round)
    // Track.
    ctx.addArc(center: center, radius: radius, startAngle: angle(0), endAngle: angle(1), clockwise: true)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(width); ctx.strokePath()

    // Filled arc, green → amber along its length (clip to the stroke, paint wedges).
    let green = rgb(0x30D158), amber = rgb(0xFFB224)
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: angle(0), endAngle: angle(value), clockwise: true)
    ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
    let slices = 240
    for i in 0..<slices {
        // Extend past both ends so the round caps get the end colours.
        let f0 = -0.08 + (value + 0.16) * CGFloat(i) / CGFloat(slices)
        let f1 = -0.08 + (value + 0.16) * CGFloat(i + 1) / CGFloat(slices) + 0.002
        let t = min(max((f0 + f1) / 2 / value, 0), 1)
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius + width, startAngle: angle(f0), endAngle: angle(f1), clockwise: true)
        ctx.closePath()
        ctx.setFillColor(lerp(green, amber, t)); ctx.fillPath()
    }
    ctx.restoreGState()

    // Pace marker: white bar across the track, with a dark halo to separate it from the fill.
    let a = point(pace, radius - width / 2 - 30), b = point(pace, radius + width / 2 + 30)
    for (w, c) in [(CGFloat(80), rgb(0x1E1B4B, 0.9)), (CGFloat(44), rgb(0xFFFFFF))] {
        ctx.move(to: a); ctx.addLine(to: b)
        ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.strokePath()
    }

    // AgentsTrack's ">_" prompt mark in the middle of the gauge (same proportions as its icon.svg).
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let u: CGFloat = 14, o = CGPoint(x: center.x - 7 * u, y: center.y + 5 * u)   // svg (16,16) -> gauge centre
    func svg(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + (x - 9) * u, y: o.y - (y - 11) * u) }
    ctx.move(to: svg(9, 11)); ctx.addLine(to: svg(14, 16)); ctx.addLine(to: svg(9, 21)); ctx.strokePath()
    ctx.move(to: svg(17, 21)); ctx.addLine(to: svg(23, 21)); ctx.strokePath()
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
