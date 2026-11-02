// ============================================================
// Draws Testify's app icon and writes AppIcon.icns.
//
//   swift make-icon.swift            # regenerate AppIcon.icns
//
// The design follows the Stack palette: a near-black tile, a laptop whose
// screen shows a report, and a purple-to-pink seal (the logo's chevron
// colours) carrying a tick. It sits on Apple's 1024px icon grid (824px body, 100px
// margin) so macOS shows it at the same size as other app icons.
// ============================================================

import AppKit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let purple = rgb(0x7E2CFF)
let pink = rgb(0xFF3292)
let nearBlack = rgb(0x1A1A1E)
let charcoal = rgb(0x26262A)
let softPurple = rgb(0xE0D0FF)
let lightPurple = rgb(0xD8B4FE)

/// Draw the icon at 1024x1024 (coordinates are on the 1024 grid; origin bottom-left).
func drawIcon() {
    // --- Tile ---
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.35)
    drop.shadowOffset = NSSize(width: 0, height: -10)
    drop.shadowBlurRadius = 24
    drop.set()
    charcoal.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: rgb(0x2E2A3A), ending: nearBlack)!.draw(in: tile, angle: -90)
    // A faint purple glow behind the seal ties the tile to the brand colour.
    NSGradient(colors: [purple.withAlphaComponent(0.45), purple.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 728, y: 296), radius: 0,
              toCenter: NSPoint(x: 728, y: 296), radius: 420, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Thin inner highlight along the tile edge.
    rgb(0xFFFFFF, 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()

    // --- Laptop, front-on: lid with a lit screen, then the base ---
    let lid = NSRect(x: 222, y: 364, width: 580, height: 392)
    let lidPath = NSBezierPath(roundedRect: lid, xRadius: 38, yRadius: 38)
    NSGraphicsContext.saveGraphicsState()
    let lidShadow = NSShadow()
    lidShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    lidShadow.shadowOffset = NSSize(width: 0, height: -14)
    lidShadow.shadowBlurRadius = 30
    lidShadow.set()
    rgb(0xE4E4EA).setFill()
    lidPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xF4F4F7), ending: rgb(0xCFCFD8))!.draw(in: lidPath, angle: -90)

    // Display: near-black bezel edge, then a light screen showing a report.
    let bezel = lid.insetBy(dx: 18, dy: 18)
    charcoal.setFill()
    NSBezierPath(roundedRect: bezel, xRadius: 22, yRadius: 22).fill()
    let screen = bezel.insetBy(dx: 12, dy: 12)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 12, yRadius: 12)
    NSGradient(starting: NSColor.white, ending: rgb(0xF3EEFF))!.draw(in: screenPath, angle: -90)

    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                     xRadius: h / 2, yRadius: h / 2).fill()
    }
    let left = screen.minX + 44
    bar(left, screen.maxY - 76, 170, 30, purple)
    bar(left, screen.maxY - 130, 300, 22, lightPurple)
    bar(left, screen.maxY - 176, 340, 22, lightPurple)
    bar(left, screen.maxY - 222, 240, 22, lightPurple)

    // Base: a slab a little wider than the lid, with the opening notch.
    let base = NSRect(x: 172, y: 324, width: 680, height: 44)
    let basePath = NSBezierPath()
    basePath.move(to: NSPoint(x: base.minX, y: base.maxY))
    basePath.line(to: NSPoint(x: base.maxX, y: base.maxY))
    basePath.line(to: NSPoint(x: base.maxX, y: base.minY + 26))
    basePath.curve(to: NSPoint(x: base.maxX - 40, y: base.minY),
                   controlPoint1: NSPoint(x: base.maxX, y: base.minY + 10),
                   controlPoint2: NSPoint(x: base.maxX - 18, y: base.minY))
    basePath.line(to: NSPoint(x: base.minX + 40, y: base.minY))
    basePath.curve(to: NSPoint(x: base.minX, y: base.minY + 26),
                   controlPoint1: NSPoint(x: base.minX + 18, y: base.minY),
                   controlPoint2: NSPoint(x: base.minX, y: base.minY + 10))
    basePath.close()
    NSGraphicsContext.saveGraphicsState()
    let baseShadow = NSShadow()
    baseShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    baseShadow.shadowOffset = NSSize(width: 0, height: -12)
    baseShadow.shadowBlurRadius = 26
    baseShadow.set()
    rgb(0xD9D9E0).setFill()
    basePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xF4F4F7), ending: rgb(0xB9B9C4))!.draw(in: basePath, angle: -90)
    rgb(0xA4A4B0).setFill()
    NSBezierPath(roundedRect: NSRect(x: 512 - 70, y: base.maxY - 14, width: 140, height: 14),
                 xRadius: 7, yRadius: 7).fill()

    // --- Seal with tick, overlapping the laptop's lower-right corner ---
    let center = NSPoint(x: 728, y: 296)
    let radius: CGFloat = 138
    let seal = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
    NSGraphicsContext.saveGraphicsState()
    let sealShadow = NSShadow()
    sealShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    sealShadow.shadowOffset = NSSize(width: 0, height: -10)
    sealShadow.shadowBlurRadius = 26
    sealShadow.set()
    purple.setFill()
    seal.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: purple, ending: pink)!.draw(in: seal, angle: -45)

    // Light rim separating the seal from the laptop.
    NSColor.white.setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
    ring.lineWidth = 16
    ring.stroke()

    // Tick proportions are relative to the seal radius.
    let k = radius / 150
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: center.x - 68 * k, y: center.y + 2 * k))
    tick.line(to: NSPoint(x: center.x - 18 * k, y: center.y - 50 * k))
    tick.line(to: NSPoint(x: center.x + 72 * k, y: center.y + 56 * k))
    tick.lineWidth = 38 * k
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    NSColor.white.setStroke()
    tick.stroke()
}

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    ctx.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Build the .iconset (each size drawn natively, not downscaled) and convert.
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let out = dir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(out.path)")

// Optional preview: `swift make-icon.swift --preview <path.png>` also writes a 1024px PNG.
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    try renderPNG(size: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
}
