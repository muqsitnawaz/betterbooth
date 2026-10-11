// Draws the app icon: a gradient squircle with a 9:16 frame and a lens. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: NSColor(red: 0.98, green: 0.36, blue: 0.33, alpha: 1),
               ending: NSColor(red: 0.55, green: 0.17, blue: 0.62, alpha: 1))!.draw(in: squircle, angle: -70)
    let fh = body.height * 0.62, fw = fh * 9 / 16
    let frame = NSRect(x: body.midX - fw / 2, y: body.midY - fh / 2, width: fw, height: fh)
    let framePath = NSBezierPath(roundedRect: frame, xRadius: fw * 0.16, yRadius: fw * 0.16)
    framePath.lineWidth = s * 0.035
    NSColor.white.withAlphaComponent(0.95).setStroke()
    framePath.stroke()
    let r = fw * 0.3
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.midX - r, y: frame.midY - r, width: 2 * r, height: 2 * r)).fill()
    let ir = r * 0.45
    NSColor(red: 0.55, green: 0.17, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.midX - ir, y: frame.midY - ir, width: 2 * ir, height: 2 * ir)).fill()
    let dr = fw * 0.07
    NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.midX - dr, y: frame.maxY - fw * 0.28, width: 2 * dr, height: 2 * dr)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
