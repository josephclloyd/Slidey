#!/usr/bin/swift

import AppKit
import CoreGraphics

func generateIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(origin: .zero, size: size)
    let cornerRadius = size.width * 0.2

    // Background gradient (blue to purple)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0).cgColor,
        NSColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1.0).cgColor
    ] as CFArray

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
    }

    // Draw three overlapping photo frames to represent a slideshow
    let frameWidth = size.width * 0.5
    let frameHeight = frameWidth * 0.75
    let frameThickness = size.width * 0.02

    // Back frame (rotated left)
    context.saveGState()
    context.translateBy(x: size.width * 0.3, y: size.height * 0.35)
    context.rotate(by: -0.15)
    drawPhotoFrame(context: context, width: frameWidth, height: frameHeight, thickness: frameThickness)
    context.restoreGState()

    // Middle frame (rotated right)
    context.saveGState()
    context.translateBy(x: size.width * 0.4, y: size.height * 0.4)
    context.rotate(by: 0.1)
    drawPhotoFrame(context: context, width: frameWidth, height: frameHeight, thickness: frameThickness)
    context.restoreGState()

    // Front frame (straight)
    context.saveGState()
    context.translateBy(x: size.width * 0.35, y: size.height * 0.45)
    drawPhotoFrame(context: context, width: frameWidth, height: frameHeight, thickness: frameThickness)
    context.restoreGState()

    image.unlockFocus()
    return image
}

func drawPhotoFrame(context: CGContext, width: CGFloat, height: CGFloat, thickness: CGFloat) {
    let frameRect = CGRect(x: -width/2, y: -height/2, width: width, height: height)
    let imageRect = frameRect.insetBy(dx: thickness, dy: thickness)

    // White frame
    context.setFillColor(NSColor.white.cgColor)
    context.fill(frameRect)

    // Dark image area
    context.setFillColor(NSColor(white: 0.3, alpha: 1.0).cgColor)
    context.fill(imageRect)

    // Add a simple mountain/photo silhouette
    let mountainPath = NSBezierPath()
    mountainPath.move(to: CGPoint(x: imageRect.minX, y: imageRect.minY))
    mountainPath.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.3, y: imageRect.minY + imageRect.height * 0.6))
    mountainPath.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.5, y: imageRect.minY + imageRect.height * 0.3))
    mountainPath.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.7, y: imageRect.minY + imageRect.height * 0.5))
    mountainPath.line(to: CGPoint(x: imageRect.maxX, y: imageRect.minY))
    mountainPath.close()

    context.setFillColor(NSColor(white: 0.5, alpha: 1.0).cgColor)
    mountainPath.fill()

    // Sun/moon circle
    let sunRadius = imageRect.width * 0.12
    let sunCenter = CGPoint(x: imageRect.maxX - imageRect.width * 0.25, y: imageRect.maxY - imageRect.height * 0.25)
    context.setFillColor(NSColor(white: 0.7, alpha: 1.0).cgColor)
    context.fillEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))
}

extension NSBezierPath {
    func fill() {
        self.fill()
    }
}

// Generate all required sizes
let sizes: [(String, CGFloat)] = [
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

let outputPath = "slidey/Assets.xcassets/AppIcon.appiconset"

for (filename, size) in sizes {
    let icon = generateIcon(size: CGSize(width: size, height: size))

    if let tiffData = icon.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filePath = "\(outputPath)/\(filename)"
        try? pngData.write(to: URL(fileURLWithPath: filePath))
        print("Generated: \(filename)")
    }
}

print("Icon generation complete!")
