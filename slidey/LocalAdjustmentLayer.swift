import Foundation
import AppKit
import CoreImage
import CoreGraphics

struct LocalAdjustmentLayer {
    var maskData: Data
    var maskWidth: Int
    var maskHeight: Int
    var adjustments: SlideshowView.ImageAdjustments

    func maskCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: maskData as CFData) else { return nil }
        return CGImage(
            width: maskWidth, height: maskHeight,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: maskWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    func maskCIImage() -> CIImage? {
        guard let cgImage = maskCGImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}

@Observable
final class LocalAdjustmentController {
    var isActive = false
    var brushRadius: Double = 40
    var adjustments: SlideshowView.ImageAdjustments = .init()
    var mousePosition: CGPoint?
    var lastPaintPixel: CGPoint?
    var hasPainted = false

    private(set) var maskContext: CGContext?
    private(set) var maskWidth: Int = 0
    private(set) var maskHeight: Int = 0
    var maskVersion: Int = 0

    func initMask(width: Int, height: Int) {
        maskWidth = width
        maskHeight = height
        maskContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        maskContext?.setFillColor(gray: 0, alpha: 1)
        maskContext?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        maskVersion = 0
        hasPainted = false
    }

    func paintDab(at center: CGPoint, pixelRadius: CGFloat) {
        guard let ctx = maskContext else { return }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
            locations: [0, 1]
        ) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.lighten)
        let rect = CGRect(
            x: center.x - pixelRadius,
            y: center.y - pixelRadius,
            width: pixelRadius * 2,
            height: pixelRadius * 2
        )
        ctx.addEllipse(in: rect)
        ctx.clip()
        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: pixelRadius,
            options: []
        )
        ctx.restoreGState()
    }

    func paintStroke(from: CGPoint, to: CGPoint, pixelRadius: CGFloat) {
        let dist = hypot(to.x - from.x, to.y - from.y)
        let step = max(1, pixelRadius * 0.25)
        let count = max(1, Int(dist / step))
        for i in 0...count {
            let t = count == 0 ? 0.0 : CGFloat(i) / CGFloat(count)
            let pt = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
            paintDab(at: pt, pixelRadius: pixelRadius)
        }
        hasPainted = true
        maskVersion += 1
    }

    func maskCGImage() -> CGImage? {
        maskContext?.makeImage()
    }

    func extractMaskData() -> Data? {
        guard let img = maskCGImage(),
              let dp = img.dataProvider,
              let data = dp.data else { return nil }
        return data as Data
    }

    func resetMask() {
        guard let ctx = maskContext else { return }
        ctx.setBlendMode(.normal)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))
        adjustments = .init()
        lastPaintPixel = nil
        hasPainted = false
        maskVersion += 1
    }

    func reset() {
        isActive = false
        maskContext = nil
        maskWidth = 0
        maskHeight = 0
        adjustments = .init()
        mousePosition = nil
        lastPaintPixel = nil
        hasPainted = false
        maskVersion = 0
    }
}
