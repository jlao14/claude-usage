// Draws the app icon (terracotta rounded square with a gauge) and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: artwork fills ~82% of the canvas.
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(
        starting: NSColor(red: 0.86, green: 0.56, blue: 0.42, alpha: 1),
        ending: NSColor(red: 0.74, green: 0.41, blue: 0.29, alpha: 1))!
        .draw(in: path, angle: -90)

    let center = NSPoint(x: s / 2, y: s * 0.40)
    let radius = tile.width * 0.30
    let line = tile.width * 0.075
    NSColor.white.setStroke()

    // Gauge arc: 210 degrees sweeping clockwise from lower left to lower right.
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 195, endAngle: -15, clockwise: true)
    arc.lineWidth = line
    arc.lineCapStyle = .round
    arc.stroke()

    // Needle pointing up and to the right.
    let angle = CGFloat.pi * 0.30
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.58, y: center.y + sin(angle) * radius * 0.58))
    needle.lineWidth = line
    needle.lineCapStyle = .round
    needle.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - line, y: center.y - line, width: line * 2, height: line * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: out.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: out.appending(path: "icon_\(base)x\(base)@2x.png"))
}
