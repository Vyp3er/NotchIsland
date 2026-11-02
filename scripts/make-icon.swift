// Erzeugt das App-Icon (AppIcon.appiconset) programmatisch.
// Aufruf: swift scripts/make-icon.swift NotchIsland/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("Usage: swift make-icon.swift <AppIcon.appiconset>")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep? {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = size / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    // Grundfläche im macOS-Raster (824 × 824 mit Rand für den Schatten).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x0E0F18).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x2E3150), color(0x15162A), color(0x07070C)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
        .draw(in: bodyPath, angle: -90)

    // Weicher Lichtschein unter der Island.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [color(0x7C6CFF, 0.45), color(0x7C6CFF, 0)])?
        .draw(fromCenter: NSPoint(x: 512, y: 640), radius: 0,
              toCenter: NSPoint(x: 512, y: 640), radius: 360, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Die Island.
    let island = NSRect(x: 232, y: 586, width: 560, height: 152)
    let islandPath = NSBezierPath(roundedRect: island, xRadius: 76, yRadius: 76)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0x000000, 0.6)
    glow.shadowBlurRadius = 30
    glow.shadowOffset = NSSize(width: 0, height: -14)
    glow.set()
    color(0x000000).setFill()
    islandPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.08).setStroke()
    islandPath.lineWidth = 3
    islandPath.stroke()

    // Mini-Cover links.
    let cover = NSRect(x: 286, y: 616, width: 92, height: 92)
    let coverPath = NSBezierPath(roundedRect: cover, xRadius: 22, yRadius: 22)
    NSGradient(colors: [color(0xFF9F43), color(0xFF4F8B)])?.draw(in: coverPath, angle: -45)

    // Equalizer rechts.
    let heights: [CGFloat] = [56, 92, 70, 40]
    for (index, height) in heights.enumerated() {
        let x = 610 + CGFloat(index) * 34
        let bar = NSRect(x: x, y: 662 - height / 2, width: 20, height: height)
        let barPath = NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10)
        NSGradient(colors: [color(0x5EF2C2), color(0x3BB3FF)])?.draw(in: barPath, angle: 90)
    }

    // Angedeutete Ablage-Kacheln darunter.
    let tileColors: [UInt32] = [0x3A3D63, 0x34375A, 0x2E3050]
    for index in 0..<3 {
        let tile = NSRect(x: 262 + CGFloat(index) * 176, y: 300, width: 148, height: 176)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 30, yRadius: 30)
        color(tileColors[index], 0.9).setFill()
        tilePath.fill()
        color(0xFFFFFF, 0.06).setStroke()
        tilePath.lineWidth = 2
        tilePath.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

struct Variant {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let variants = [16, 32, 128, 256, 512].flatMap { [Variant(points: $0, scale: 1), Variant(points: $0, scale: 2)] }
var images: [[String: String]] = []
for variant in variants {
    guard let rep = drawIcon(size: CGFloat(variant.pixels)),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: output.appendingPathComponent(variant.filename))
    images.append([
        "filename": variant.filename,
        "idiom": "mac",
        "scale": "\(variant.scale)x",
        "size": "\(variant.points)x\(variant.points)",
    ])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Icon written to \(output.path)")
