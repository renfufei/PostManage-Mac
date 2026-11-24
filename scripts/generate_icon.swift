import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let artwork = root.appendingPathComponent("Artwork/PostManageIcon.png")
let iconset = root.appendingPathComponent("PostManage/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let main = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 210, yRadius: 210)
let shadow = NSShadow()
shadow.shadowColor = color(6, 22, 32, 0.35)
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSGradient(starting: color(19, 58, 72), ending: color(12, 32, 48))!.draw(in: main, angle: 110)
NSShadow().set()

let stripe = NSBezierPath(roundedRect: NSRect(x: 165, y: 485, width: 694, height: 16), xRadius: 8, yRadius: 8)
color(78, 117, 129, 0.5).setFill()
stripe.fill()

func drawCentered(_ string: String, y: CGFloat, fontSize: CGFloat, fill: NSColor) {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: fill,
        .kern: -7
    ]
    let measured = (string as NSString).size(withAttributes: attributes)
    (string as NSString).draw(at: NSPoint(x: (CGFloat(size) - measured.width) / 2,
                                          y: y), withAttributes: attributes)
}

drawCentered("POST", y: 570, fontSize: 175, fill: color(255, 183, 115))
drawCentered("GET", y: 237, fontSize: 224, fill: color(107, 232, 192))

let dot = NSBezierPath(ovalIn: NSRect(x: 770, y: 747, width: 46, height: 46))
color(107, 232, 192).setFill()
dot.fill()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
try data.write(to: artwork)

let sizes: [(String, Int, Int)] = [
    ("icon_16x16.png", 16, 1), ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1), ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1), ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1), ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1), ("icon_512x512@2x.png", 512, 2)
]
var images: [[String: String]] = []
for (filename, points, scale) in sizes {
    let pixels = points * scale
    let output = iconset.appendingPathComponent(filename)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", String(pixels), String(pixels), artwork.path, "--out", output.path]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("Could not resize icon") }
    images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: iconset.appendingPathComponent("Contents.json"))
print("Created \(artwork.path) and AppIcon asset catalog")
