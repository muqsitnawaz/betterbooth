// Draws the app icon: a graphite squircle holding a glass lens. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: rgb(0.30, 0.31, 0.34), ending: rgb(0.11, 0.11, 0.13))!.draw(in: squircle, angle: -90)

    let c = NSPoint(x: body.midX, y: body.midY - body.height * 0.02)
    let r = body.width * 0.33
    NSGradient(starting: rgb(0.86, 0.87, 0.89), ending: rgb(0.45, 0.46, 0.49))!.draw(in: circle(c, r), angle: -60)
    rgb(0.07, 0.07, 0.09).setFill()
    circle(c, r * 0.86).fill()
    NSGradient(colors: [rgb(0.20, 0.32, 0.62), rgb(0.42, 0.20, 0.55), rgb(0.03, 0.03, 0.05)],
               atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        .draw(fromCenter: NSPoint(x: c.x + r * 0.18, y: c.y + r * 0.2), radius: 0, toCenter: c, radius: r * 0.66, options: [])
    rgb(0.01, 0.01, 0.02).setFill()
    circle(c, r * 0.28).fill()
    rgb(1, 1, 1, 0.85).setFill()
    circle(NSPoint(x: c.x - r * 0.3, y: c.y + r * 0.32), r * 0.09).fill()

    rgb(1, 0.27, 0.23).setFill()
    circle(NSPoint(x: body.maxX - body.width * 0.16, y: body.maxY - body.width * 0.16), body.width * 0.045).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
