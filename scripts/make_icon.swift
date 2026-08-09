import AppKit
import Foundation

// Generates Assets/AppIcon.iconset. Uses the official Codex icon
// (Assets/AppIcon-source.png) when present; otherwise falls back to a simple
// generated ">_" icon so the project stays self-contained. Run from project root.

let fileManager = FileManager.default
let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceURL = cwd.appendingPathComponent("Assets/AppIcon-source.png")
let outputDir = cwd.appendingPathComponent("Assets/AppIcon.iconset")
try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

let hasSource = fileManager.fileExists(atPath: sourceURL.path)
let source: NSImage? = hasSource ? NSImage(contentsOf: sourceURL) : nil
if !hasSource {
    print("AppIcon-source.png not found; using generated fallback icon.")
}

func drawFallback(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let cg = context.cgContext
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    let radius = side * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.addPath(path)
    cg.setFillColor(NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.20, alpha: 1).cgColor)
    cg.fillPath()

    let font = NSFont.monospacedSystemFont(ofSize: side * 0.42, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let text = NSAttributedString(string: ">_", attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2))

    let dotRadius = side * 0.075
    let dotCenter = CGPoint(x: side * 0.76, y: side * 0.24)
    let dotRect = CGRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    cg.setFillColor(NSColor.systemGreen.cgColor)
    cg.fillEllipse(in: dotRect)

    return rep.representation(using: .png, properties: [:])
}

func render(size: Int) -> Data? {
    if let source {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
    return drawFallback(size: size)
}

let specs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    guard let data = render(size: spec.size) else {
        fputs("failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    do {
        try data.write(to: outputDir.appendingPathComponent(spec.name))
    } catch {
        fputs("failed to write \(spec.name): \(error)\n", stderr)
        exit(1)
    }
}

print("Generated Assets/AppIcon.iconset")
