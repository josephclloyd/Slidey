import Foundation
import CoreGraphics
import SwiftUI

struct CropRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var isValid: Bool { width > 0.005 && height > 0.005 }

    func clamped() -> CropRegion {
        let cx = max(0, min(1, x))
        let cy = max(0, min(1, y))
        return CropRegion(
            x: cx, y: cy,
            width: min(max(0, width), 1 - cx),
            height: min(max(0, height), 1 - cy)
        )
    }

    func normalized() -> CropRegion {
        var r = self
        if r.width < 0 { r.x += r.width; r.width = -r.width }
        if r.height < 0 { r.y += r.height; r.height = -r.height }
        return r.clamped()
    }

    static func fromPoints(_ a: CGPoint, _ b: CGPoint) -> CropRegion {
        CropRegion(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        ).clamped()
    }
}

// MARK: - Aspect ratio presets

enum CropAspectPreset: String, CaseIterable, Identifiable {
    case free
    case square
    case ratio4x3
    case ratio3x2
    case ratio16x9
    case a4Portrait
    case a4Landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .ratio4x3: return "4:3"
        case .ratio3x2: return "3:2"
        case .ratio16x9: return "16:9"
        case .a4Portrait: return "A4 ↕"
        case .a4Landscape: return "A4 ↔"
        }
    }

    /// Target width:height ratio in pixel space; nil for unconstrained (Free).
    var pixelRatio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .ratio4x3: return 4.0 / 3.0
        case .ratio3x2: return 3.0 / 2.0
        case .ratio16x9: return 16.0 / 9.0
        case .a4Portrait: return 210.0 / 297.0
        case .a4Landscape: return 297.0 / 210.0
        }
    }
}

// MARK: - CropController

@Observable
final class CropController {
    var isActive = false
    var pendingRegion: CropRegion?
    var isDragging = false
    var dragStartNormalized: CGPoint?
    var dragCurrentNormalized: CGPoint?
    var activeHandle: Handle?
    var regionBeforeDrag: CropRegion?
    var activePreset: CropAspectPreset = .free

    enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }

    func reset() {
        isActive = false
        pendingRegion = nil
        isDragging = false
        dragStartNormalized = nil
        dragCurrentNormalized = nil
        activeHandle = nil
        regionBeforeDrag = nil
    }

    var displayRegion: CropRegion? {
        if let pending = pendingRegion { return pending }
        if isDragging,
           let start = dragStartNormalized,
           let current = dragCurrentNormalized {
            let region = CropRegion.fromPoints(start, current)
            return region.isValid ? region : nil
        }
        return nil
    }

    // MARK: - Coordinate conversion

    static func viewToNormalized(
        point: CGPoint,
        containerSize: CGSize,
        fittedSize: CGSize,
        zoomScale: CGFloat,
        imageOffset: CGSize,
        rotationAngle: Angle
    ) -> CGPoint {
        let relX = point.x - containerSize.width / 2 - imageOffset.width
        let relY = point.y - containerSize.height / 2 - imageOffset.height
        let unzX = relX / zoomScale
        let unzY = relY / zoomScale
        let a = rotationAngle.radians
        let c = cos(a), s = sin(a)
        let modelX = unzX * c + unzY * s
        let modelY = -unzX * s + unzY * c
        guard fittedSize.width > 0, fittedSize.height > 0 else { return .zero }
        return CGPoint(
            x: modelX / fittedSize.width + 0.5,
            y: modelY / fittedSize.height + 0.5
        )
    }

    static func normalizedToView(
        point: CGPoint,
        containerSize: CGSize,
        fittedSize: CGSize,
        zoomScale: CGFloat,
        imageOffset: CGSize,
        rotationAngle: Angle
    ) -> CGPoint {
        let modelX = (point.x - 0.5) * fittedSize.width
        let modelY = (point.y - 0.5) * fittedSize.height
        let a = rotationAngle.radians
        let c = cos(a), s = sin(a)
        let rotX = modelX * c - modelY * s
        let rotY = modelX * s + modelY * c
        return CGPoint(
            x: rotX * zoomScale + containerSize.width / 2 + imageOffset.width,
            y: rotY * zoomScale + containerSize.height / 2 + imageOffset.height
        )
    }

    static func fittedImageSize(
        imagePixelSize: CGSize,
        containerSize: CGSize,
        rotationAngle: Angle
    ) -> CGSize {
        let bb = rotatedBoundingBox(imagePixelSize, by: rotationAngle)
        guard bb.width > 0, bb.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let fitScale = min(containerSize.width / bb.width, containerSize.height / bb.height)
        return CGSize(width: imagePixelSize.width * fitScale, height: imagePixelSize.height * fitScale)
    }

    static func constrainToAspectRatio(
        start: CGPoint, end: CGPoint, aspectRatio: CGFloat
    ) -> CGPoint {
        guard aspectRatio > 0 else { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let desiredHeight = abs(dx) / aspectRatio
        return CGPoint(x: end.x, y: start.y + (dy >= 0 ? desiredHeight : -desiredHeight))
    }

    /// Converts a pixel-space width:height ratio into a normalized-space
    /// width/height ratio (normalized coords stretch each axis independently).
    static func normalizedAspect(pixelRatio: CGFloat, imagePixelSize: CGSize) -> CGFloat? {
        guard pixelRatio > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }
        return pixelRatio * imagePixelSize.height / imagePixelSize.width
    }

    /// Resizes a region to match `normAspect` (normalized width/height) while
    /// keeping its centre fixed and staying within the unit square.
    static func fitRegion(_ region: CropRegion, toNormAspect normAspect: CGFloat) -> CropRegion {
        guard normAspect > 0 else { return region }
        let cx = region.x + region.width / 2
        let cy = region.y + region.height / 2
        var w = region.width
        var h = w / normAspect
        if h > region.height {
            h = region.height
            w = h * normAspect
        }
        w = min(w, 1)
        h = min(h, 1)
        let x = min(max(cx - w / 2, 0), 1 - w)
        let y = min(max(cy - h / 2, 0), 1 - h)
        return CropRegion(x: x, y: y, width: w, height: h)
    }

    // MARK: - Handle positions (normalized coords)

    func handlePositions() -> [(Handle, CGPoint)] {
        guard let r = displayRegion else { return [] }
        let minX = r.x, minY = r.y
        let maxX = r.x + r.width, maxY = r.y + r.height
        let midX = r.x + r.width / 2, midY = r.y + r.height / 2
        return [
            (.topLeft, CGPoint(x: minX, y: minY)),
            (.topRight, CGPoint(x: maxX, y: minY)),
            (.bottomLeft, CGPoint(x: minX, y: maxY)),
            (.bottomRight, CGPoint(x: maxX, y: maxY)),
            (.top, CGPoint(x: midX, y: minY)),
            (.bottom, CGPoint(x: midX, y: maxY)),
            (.left, CGPoint(x: minX, y: midY)),
            (.right, CGPoint(x: maxX, y: midY)),
        ]
    }

    func applyHandleDrag(handle: Handle, to point: CGPoint, normAspect: CGFloat? = nil) {
        guard let r = regionBeforeDrag else { return }
        if let na = normAspect, na > 0 {
            pendingRegion = CropController.constrainedHandleRegion(
                from: r, handle: handle, point: point, normAspect: na
            ).normalized()
            return
        }
        let p = point
        let result: CropRegion
        switch handle {
        case .topLeft:
            result = CropRegion(x: p.x, y: p.y,
                                width: r.x + r.width - p.x, height: r.y + r.height - p.y)
        case .topRight:
            result = CropRegion(x: r.x, y: p.y,
                                width: p.x - r.x, height: r.y + r.height - p.y)
        case .bottomLeft:
            result = CropRegion(x: p.x, y: r.y,
                                width: r.x + r.width - p.x, height: p.y - r.y)
        case .bottomRight:
            result = CropRegion(x: r.x, y: r.y,
                                width: p.x - r.x, height: p.y - r.y)
        case .top:
            result = CropRegion(x: r.x, y: p.y,
                                width: r.width, height: r.y + r.height - p.y)
        case .bottom:
            result = CropRegion(x: r.x, y: r.y,
                                width: r.width, height: p.y - r.y)
        case .left:
            result = CropRegion(x: p.x, y: r.y,
                                width: r.x + r.width - p.x, height: r.height)
        case .right:
            result = CropRegion(x: r.x, y: r.y,
                                width: p.x - r.x, height: r.height)
        }
        pendingRegion = result.normalized()
    }

    /// Computes a handle-drag result locked to `normAspect`. Corner handles keep
    /// the opposite corner fixed and drive off the axis with larger travel; edge
    /// handles keep the opposite edge fixed and derive the perpendicular
    /// dimension, centred on the dragged edge's midpoint.
    static func constrainedHandleRegion(
        from r: CropRegion, handle: Handle, point p: CGPoint, normAspect na: CGFloat
    ) -> CropRegion {
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let anchor: CGPoint
            switch handle {
            case .topLeft: anchor = CGPoint(x: r.x + r.width, y: r.y + r.height)
            case .topRight: anchor = CGPoint(x: r.x, y: r.y + r.height)
            case .bottomLeft: anchor = CGPoint(x: r.x + r.width, y: r.y)
            default: anchor = CGPoint(x: r.x, y: r.y)
            }
            let dw = p.x - anchor.x
            let dh = p.y - anchor.y
            let signW: CGFloat = dw >= 0 ? 1 : -1
            let signH: CGFloat = dh >= 0 ? 1 : -1
            var width = dw
            var height = dh
            if abs(dw) >= abs(dh) * na {
                height = signH * abs(dw) / na
            } else {
                width = signW * abs(dh) * na
            }
            return CropRegion(x: anchor.x, y: anchor.y, width: width, height: height)
        case .left, .right:
            let fixedX = handle == .left ? r.x + r.width : r.x
            let cy = r.y + r.height / 2
            let w = abs(fixedX - p.x)
            let h = w / na
            let x = min(fixedX, p.x)
            return CropRegion(x: x, y: cy - h / 2, width: w, height: h)
        case .top, .bottom:
            let fixedY = handle == .top ? r.y + r.height : r.y
            let cx = r.x + r.width / 2
            let h = abs(fixedY - p.y)
            let w = h * na
            let y = min(fixedY, p.y)
            return CropRegion(x: cx - w / 2, y: y, width: w, height: h)
        }
    }
}
