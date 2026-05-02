import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon.iconset")
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconImage {
    let name: String
    let size: Int
}

let images = [
    IconImage(name: "icon_16x16.png", size: 16),
    IconImage(name: "icon_16x16@2x.png", size: 32),
    IconImage(name: "icon_32x32.png", size: 32),
    IconImage(name: "icon_32x32@2x.png", size: 64),
    IconImage(name: "icon_128x128.png", size: 128),
    IconImage(name: "icon_128x128@2x.png", size: 256),
    IconImage(name: "icon_256x256.png", size: 256),
    IconImage(name: "icon_256x256@2x.png", size: 512),
    IconImage(name: "icon_512x512.png", size: 512),
    IconImage(name: "icon_512x512@2x.png", size: 1024),
]

for image in images {
    let nsImage = NSImage(size: NSSize(width: image.size, height: image.size))
    nsImage.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: image.size, height: image.size)
    let scale = CGFloat(image.size) / 1024
    let cornerRadius = 220 * scale

    NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 64 * scale, dy: 64 * scale), xRadius: cornerRadius, yRadius: cornerRadius).fill()

    NSColor(calibratedRed: 0.03, green: 0.16, blue: 0.31, alpha: 0.28).setFill()
    NSBezierPath(roundedRect: NSRect(x: 160 * scale, y: 250 * scale, width: 704 * scale, height: 500 * scale), xRadius: 56 * scale, yRadius: 56 * scale).fill()

    NSColor.white.withAlphaComponent(0.94).setFill()
    NSBezierPath(roundedRect: NSRect(x: 188 * scale, y: 286 * scale, width: 648 * scale, height: 420 * scale), xRadius: 42 * scale, yRadius: 42 * scale).fill()

    NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 188 * scale, y: 650 * scale, width: 648 * scale, height: 56 * scale), xRadius: 42 * scale, yRadius: 42 * scale).fill()

    NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.95, alpha: 1).setStroke()
    let arrowLine = NSBezierPath()
    arrowLine.lineWidth = 46 * scale
    arrowLine.lineCapStyle = .round
    arrowLine.move(to: NSPoint(x: 318 * scale, y: 498 * scale))
    arrowLine.line(to: NSPoint(x: 666 * scale, y: 498 * scale))
    arrowLine.stroke()

    let rightArrow = NSBezierPath()
    rightArrow.move(to: NSPoint(x: 666 * scale, y: 498 * scale))
    rightArrow.line(to: NSPoint(x: 584 * scale, y: 574 * scale))
    rightArrow.line(to: NSPoint(x: 584 * scale, y: 422 * scale))
    rightArrow.close()
    rightArrow.fill()

    NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.42, alpha: 1).setStroke()
    let returnLine = NSBezierPath()
    returnLine.lineWidth = 46 * scale
    returnLine.lineCapStyle = .round
    returnLine.move(to: NSPoint(x: 706 * scale, y: 390 * scale))
    returnLine.line(to: NSPoint(x: 358 * scale, y: 390 * scale))
    returnLine.stroke()

    let leftArrow = NSBezierPath()
    leftArrow.move(to: NSPoint(x: 358 * scale, y: 390 * scale))
    leftArrow.line(to: NSPoint(x: 440 * scale, y: 466 * scale))
    leftArrow.line(to: NSPoint(x: 440 * scale, y: 314 * scale))
    leftArrow.close()
    leftArrow.fill()

    NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 260 * scale, y: 586 * scale, width: 60 * scale, height: 28 * scale), xRadius: 14 * scale, yRadius: 14 * scale).fill()
    NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.42, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 340 * scale, y: 586 * scale, width: 150 * scale, height: 28 * scale), xRadius: 14 * scale, yRadius: 14 * scale).fill()

    nsImage.unlockFocus()

    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }

    try png.write(to: outputURL.appendingPathComponent(image.name))
}
