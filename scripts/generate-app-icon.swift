// Generates the Nudge app icon set from the 👋 emoji.
//
// Usage:
//   swift scripts/generate-app-icon.swift
//
// Writes wave-{16,32,64,128,256,512,1024}.png + Contents.json into
// boringNotch/Assets.xcassets/AppIcon.appiconset/. Re-run any time you
// want to tweak the emoji, background gradient, or sizing.

import AppKit
import Foundation

let emoji = "👋"
let outputDir = "boringNotch/Assets.xcassets/AppIcon.appiconset"

func renderIcon(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        fatalError("Could not create bitmap rep at \(pixels)px")
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let p = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: p, height: p)
    // Apple's rounded-square corner ratio is ~22.5% of the side.
    let corner = p * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    // Light sky-blue gradient.
    let top = NSColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1.0)
    let bottom = NSColor(red: 0.35, green: 0.65, blue: 0.92, alpha: 1.0)
    if let gradient = NSGradient(starting: top, ending: bottom) {
        gradient.draw(in: path, angle: 270)
    }

    // The emoji. Render it at ~68% of the canvas; macOS picks the right
    // sbix variant of Apple Color Emoji for the requested point size.
    let fontSize = p * 0.68
    let font = NSFont.systemFont(ofSize: fontSize)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: style
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let strSize = str.size()
    // Slight vertical nudge — emoji glyphs sit a touch high in their box.
    let drawRect = NSRect(
        x: (p - strSize.width) / 2,
        y: (p - strSize.height) / 2 - p * 0.02,
        width: strSize.width,
        height: strSize.height
    )
    str.draw(in: drawRect)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed at \(pixels)px")
    }
    return data
}

// All distinct pixel sizes the macOS icon set needs:
//   16x1=16, 16x2=32, 32x1=32, 32x2=64, 128x1=128, 128x2=256,
//   256x1=256, 256x2=512, 512x1=512, 512x2=1024
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let data = renderIcon(pixels: size)
    let path = "\(outputDir)/wave-\(size).png"
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  (\(data.count) bytes)")
}

let contents: [String: Any] = [
    "images": [
        ["filename": "wave-16.png",   "idiom": "mac", "scale": "1x", "size": "16x16"],
        ["filename": "wave-32.png",   "idiom": "mac", "scale": "2x", "size": "16x16"],
        ["filename": "wave-32.png",   "idiom": "mac", "scale": "1x", "size": "32x32"],
        ["filename": "wave-64.png",   "idiom": "mac", "scale": "2x", "size": "32x32"],
        ["filename": "wave-128.png",  "idiom": "mac", "scale": "1x", "size": "128x128"],
        ["filename": "wave-256.png",  "idiom": "mac", "scale": "2x", "size": "128x128"],
        ["filename": "wave-256.png",  "idiom": "mac", "scale": "1x", "size": "256x256"],
        ["filename": "wave-512.png",  "idiom": "mac", "scale": "2x", "size": "256x256"],
        ["filename": "wave-512.png",  "idiom": "mac", "scale": "1x", "size": "512x512"],
        ["filename": "wave-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"],
    ],
    "info": [
        "author": "nudge",
        "version": 1
    ]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(outputDir)/Contents.json"))
print("wrote \(outputDir)/Contents.json")
