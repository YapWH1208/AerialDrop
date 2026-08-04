#!/usr/bin/env swift
// Renders the AerialDrop app icon (liquid-glass squircle with the sparkles.tv
// glyph on a night-sky aurora) into Assets/AppIcon.icns.
import AppKit

let assetsDir = URL(fileURLWithPath: "Assets", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
let iconsetDir = assetsDir.appendingPathComponent("AppIcon.iconset")

func drawIcon(side: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let path = NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237)
    path.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.20, alpha: 1)
    ])!
    background.draw(in: rect, angle: -90)

    let teal = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.75, blue: 0.78, alpha: 0.55),
        NSColor(calibratedRed: 0.20, green: 0.75, blue: 0.78, alpha: 0)
    ])!
    teal.draw(in: rect, relativeCenterPosition: NSPoint(x: 0.5, y: 0.66))

    let violet = NSGradient(colors: [
        NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.85, alpha: 0.40),
        NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.85, alpha: 0)
    ])!
    violet.draw(in: rect, relativeCenterPosition: NSPoint(x: 0.42, y: 0.30))

    let highlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.28),
        NSColor(calibratedWhite: 1.0, alpha: 0.0)
    ])!
    highlight.draw(in: NSRect(x: 0, y: side * 0.72, width: side, height: side * 0.28), angle: 90)

    let glyphSize = side * 0.62
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(0.97)]))
    if let symbol = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let origin = NSPoint(x: (side - glyphSize) / 2, y: (side - glyphSize) / 2)
        symbol.draw(in: NSRect(origin: origin, size: NSSize(width: glyphSize, height: glyphSize)))
    }
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(side: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
for size in sizes {
    let data = renderPNG(pixels: size.pixels)
    try data.write(to: iconsetDir.appendingPathComponent("\(size.name).png"))
    print("Wrote \(size.name).png")
}

let icnsURL = assetsDir.appendingPathComponent("AppIcon.icns")
try FileManager.default.removeItemIfExists(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
try FileManager.default.removeItem(at: iconsetDir)
print("Created \(icnsURL.path)")

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
