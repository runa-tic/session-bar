// Draws Resources/AppIcon.icns: swift scripts/make-icon.swift
// Only needed again when the icon should change; the result is checked in.
import AppKit

func draw(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024

    // The macOS icon shape: a rounded square inset from the canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.38, blue: 0.86, alpha: 1),
               ending: NSColor(srgbRed: 0.15, green: 0.17, blue: 0.45, alpha: 1))!
        .draw(in: shape, angle: -90)

    let symbol = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 420 * scale, weight: .medium)
            .applying(.init(paletteColors: [.white])))!
    let glyph = symbol.size
    symbol.draw(in: NSRect(x: tile.midX - glyph.width / 2, y: tile.midY - glyph.height / 2,
                           width: glyph.width, height: glyph.height))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
