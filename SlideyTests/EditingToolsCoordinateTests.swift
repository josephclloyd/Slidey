import SwiftUI
import AppKit
import XCTest
import CoreGraphics
@testable import Slidey

// These tests fill coverage gaps for the newer editing tools' coordinate and
// mask-transform logic. Model structs (PerspectiveCorners, CurvePoints, CurvesData,
// LocalAdjustmentLayer, LocalAdjustmentController) and the crop coordinate-conversion
// math are already covered in SlideyAppTests / SlideshowViewTests; this file targets
// what those don't reach: ObjectRemovalController's mask, CropController's handle /
// display-region logic, and the image-space transforms whose top-down/bottom-up
// coordinate handling is exactly the recurring Y-axis bug class (see CLAUDE.md).

// MARK: - Grayscale mask pixel reader
//
// The editing masks are 8-bit single-channel (deviceGray, alpha .none) CGContexts.
// Re-render the produced CGImage into a tightly-packed buffer (bytesPerRow == width)
// so a pixel can be read by simple `buffer[y * width + x]` indexing. Assertions target
// the geometric center and far corners, which are symmetric under a vertical flip, so
// they hold regardless of the context's origin convention.
private func maskPixel(_ cg: CGImage, x: Int, y: Int) -> UInt8 {
    let w = cg.width
    let h = cg.height
    var buffer = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(
        data: &buffer, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buffer[y * w + x]
}

private func assertPointEqual(
    _ actual: CGPoint?,
    _ expected: CGPoint,
    accuracy: CGFloat = 1e-10,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertNotNil(actual, file: file, line: line)
    guard let actual else { return }
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
}

// MARK: - Image helpers

/// An image whose visual top half is `top` and bottom half is `bottom`.
/// NSGraphicsContext uses a bottom-left origin, so the higher-y rect is the visual top.
private func makeVerticalSplitImage(size: Int, top: NSColor, bottom: NSColor) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    bottom.setFill()
    NSRect(x: 0, y: 0, width: size, height: size / 2).fill()
    top.setFill()
    NSRect(x: 0, y: size / 2, width: size, height: size - size / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

private func makeSolidImage(size: Int) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

private func centerColor(of image: NSImage) -> NSColor? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
        .usingColorSpace(.deviceRGB)
}

// MARK: - ObjectRemovalController Mask Tests

final class ObjectRemovalControllerTests: XCTestCase {
    func testInitialState() {
        let controller = ObjectRemovalController()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.hasPainted)
        XCTAssertEqual(controller.maskWidth, 0)
        XCTAssertEqual(controller.maskHeight, 0)
        XCTAssertEqual(controller.maskVersion, 0)
        XCTAssertNil(controller.maskCGImage())
    }

    func testInitMaskProducesBlackMask() {
        let controller = ObjectRemovalController()
        controller.initMask(width: 80, height: 60)
        XCTAssertEqual(controller.maskWidth, 80)
        XCTAssertEqual(controller.maskHeight, 60)
        XCTAssertFalse(controller.hasPainted)
        let cg = controller.maskCGImage()!
        XCTAssertEqual(cg.width, 80)
        XCTAssertEqual(cg.height, 60)
        XCTAssertEqual(maskPixel(cg, x: 40, y: 30), 0)
    }

    func testPaintStrokeFillsSolidWhiteWithinRadius() {
        let controller = ObjectRemovalController()
        controller.initMask(width: 100, height: 100)
        controller.paintStroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), pixelRadius: 30)
        XCTAssertTrue(controller.hasPainted)
        XCTAssertEqual(controller.maskVersion, 1)
        let cg = controller.maskCGImage()!
        // Solid ellipse: center fully white, far corner untouched (black).
        XCTAssertEqual(maskPixel(cg, x: 50, y: 50), 255)
        XCTAssertEqual(maskPixel(cg, x: 0, y: 0), 0)
    }

    func testPaintStrokeAlongLineCoversEndpoints() {
        let controller = ObjectRemovalController()
        controller.initMask(width: 100, height: 100)
        controller.paintStroke(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50), pixelRadius: 8)
        let cg = controller.maskCGImage()!
        XCTAssertEqual(maskPixel(cg, x: 20, y: 50), 255)
        XCTAssertEqual(maskPixel(cg, x: 50, y: 50), 255)
        XCTAssertEqual(maskPixel(cg, x: 80, y: 50), 255)
        // A row far from the stroke stays black.
        XCTAssertEqual(maskPixel(cg, x: 50, y: 5), 0)
    }

    func testMaskVersionIncrementsPerStroke() {
        let controller = ObjectRemovalController()
        controller.initMask(width: 50, height: 50)
        controller.paintStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10), pixelRadius: 5)
        controller.paintStroke(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 30, y: 30), pixelRadius: 5)
        XCTAssertEqual(controller.maskVersion, 2)
    }

    func testResetClearsEverything() {
        let controller = ObjectRemovalController()
        controller.isActive = true
        controller.initMask(width: 30, height: 30)
        controller.paintStroke(from: CGPoint(x: 15, y: 15), to: CGPoint(x: 15, y: 15), pixelRadius: 10)
        controller.reset()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.maskWidth, 0)
        XCTAssertEqual(controller.maskHeight, 0)
        XCTAssertFalse(controller.hasPainted)
        XCTAssertEqual(controller.maskVersion, 0)
        XCTAssertNil(controller.maskCGImage())
    }
}

// MARK: - CropController Handle & Display Region Tests

final class CropControllerHandleTests: XCTestCase {
    func testHandlePositionsEmptyWithoutRegion() {
        let controller = CropController()
        XCTAssertTrue(controller.handlePositions().isEmpty)
    }

    func testHandlePositionsForPendingRegion() {
        let controller = CropController()
        controller.pendingRegion = CropRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let positions = Dictionary(uniqueKeysWithValues: controller.handlePositions())
        XCTAssertEqual(positions.count, 8)
        assertPointEqual(positions[.topLeft], CGPoint(x: 0.2, y: 0.3))
        assertPointEqual(positions[.topRight], CGPoint(x: 0.6, y: 0.3))
        assertPointEqual(positions[.bottomLeft], CGPoint(x: 0.2, y: 0.5))
        assertPointEqual(positions[.bottomRight], CGPoint(x: 0.6, y: 0.5))
        assertPointEqual(positions[.top], CGPoint(x: 0.4, y: 0.3))
        assertPointEqual(positions[.bottom], CGPoint(x: 0.4, y: 0.5))
        assertPointEqual(positions[.left], CGPoint(x: 0.2, y: 0.4))
        assertPointEqual(positions[.right], CGPoint(x: 0.6, y: 0.4))
    }

    func testDisplayRegionPrefersPendingRegion() {
        let controller = CropController()
        let region = CropRegion(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        controller.pendingRegion = region
        XCTAssertEqual(controller.displayRegion, region)
    }

    func testDisplayRegionFromActiveDrag() {
        let controller = CropController()
        controller.isDragging = true
        controller.dragStartNormalized = CGPoint(x: 0.2, y: 0.2)
        controller.dragCurrentNormalized = CGPoint(x: 0.7, y: 0.6)
        let region = controller.displayRegion
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.x ?? -1, 0.2, accuracy: 1e-10)
        XCTAssertEqual(region?.y ?? -1, 0.2, accuracy: 1e-10)
        XCTAssertEqual(region?.width ?? -1, 0.5, accuracy: 1e-10)
        XCTAssertEqual(region?.height ?? -1, 0.4, accuracy: 1e-10)
    }

    func testDisplayRegionNilWhenTinyDrag() {
        let controller = CropController()
        controller.isDragging = true
        controller.dragStartNormalized = CGPoint(x: 0.2, y: 0.2)
        controller.dragCurrentNormalized = CGPoint(x: 0.201, y: 0.201)
        XCTAssertNil(controller.displayRegion)
    }

    func testDisplayRegionNilWhenIdle() {
        let controller = CropController()
        XCTAssertNil(controller.displayRegion)
    }

    func testResetClearsAllState() {
        let controller = CropController()
        controller.isActive = true
        controller.pendingRegion = CropRegion(x: 0, y: 0, width: 1, height: 1)
        controller.isDragging = true
        controller.dragStartNormalized = CGPoint(x: 0.1, y: 0.1)
        controller.dragCurrentNormalized = CGPoint(x: 0.2, y: 0.2)
        controller.activeHandle = .topLeft
        controller.regionBeforeDrag = CropRegion(x: 0, y: 0, width: 0.5, height: 0.5)
        controller.reset()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.pendingRegion)
        XCTAssertFalse(controller.isDragging)
        XCTAssertNil(controller.dragStartNormalized)
        XCTAssertNil(controller.dragCurrentNormalized)
        XCTAssertNil(controller.activeHandle)
        XCTAssertNil(controller.regionBeforeDrag)
    }

    func testHandleDragTopKeepsWidthMovesTopEdge() {
        let controller = CropController()
        controller.pendingRegion = CropRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.3)
        controller.regionBeforeDrag = controller.pendingRegion
        controller.applyHandleDrag(handle: .top, to: CGPoint(x: 0.5, y: 0.1))
        let r = controller.pendingRegion!
        XCTAssertEqual(r.x, 0.2, accuracy: 1e-10)
        XCTAssertEqual(r.y, 0.1, accuracy: 1e-10)
        XCTAssertEqual(r.width, 0.4, accuracy: 1e-10)
        XCTAssertEqual(r.height, 0.5, accuracy: 1e-10)
    }

    func testHandleDragRightKeepsHeightMovesRightEdge() {
        let controller = CropController()
        controller.pendingRegion = CropRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.3)
        controller.regionBeforeDrag = controller.pendingRegion
        controller.applyHandleDrag(handle: .right, to: CGPoint(x: 0.9, y: 0.5))
        let r = controller.pendingRegion!
        XCTAssertEqual(r.x, 0.2, accuracy: 1e-10)
        XCTAssertEqual(r.y, 0.3, accuracy: 1e-10)
        XCTAssertEqual(r.width, 0.7, accuracy: 1e-10)
        XCTAssertEqual(r.height, 0.3, accuracy: 1e-10)
    }

    func testHandleDragWithoutRegionBeforeDragIsNoOp() {
        let controller = CropController()
        controller.pendingRegion = CropRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.3)
        controller.regionBeforeDrag = nil
        controller.applyHandleDrag(handle: .bottomRight, to: CGPoint(x: 0.9, y: 0.9))
        XCTAssertEqual(controller.pendingRegion, CropRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.3))
    }
}

// MARK: - Crop Transform Tests (top-down normalized -> bottom-left CIImage)

final class CropTransformTests: XCTestCase {
    func testFullFrameCropPreservesSize() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 100)
        let result = view.applyCropToImage(image, region: CropRegion(x: 0, y: 0, width: 1, height: 1))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width ?? 0, 100, accuracy: 1)
        XCTAssertEqual(result?.size.height ?? 0, 100, accuracy: 1)
    }

    func testSubRegionCropShrinksImage() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 100)
        let result = view.applyCropToImage(image, region: CropRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width ?? 0, 50, accuracy: 1)
        XCTAssertEqual(result?.size.height ?? 0, 50, accuracy: 1)
    }

    // Normalized coordinates use a top-left origin; CIImage uses bottom-left. This test
    // pins that flip: cropping the normalized *top* half must extract the visual top.
    func testTopHalfCropExtractsVisualTop() {
        let view = SlideshowView()
        let image = makeVerticalSplitImage(size: 100, top: .red, bottom: .blue)
        let cropped = view.applyCropToImage(image, region: CropRegion(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertNotNil(cropped)
        let color = centerColor(of: cropped!)
        XCTAssertNotNil(color)
        XCTAssertGreaterThan(color!.redComponent, 0.5, "Top-half crop should be red")
        XCTAssertLessThan(color!.blueComponent, 0.5)
    }

    func testBottomHalfCropExtractsVisualBottom() {
        let view = SlideshowView()
        let image = makeVerticalSplitImage(size: 100, top: .red, bottom: .blue)
        let cropped = view.applyCropToImage(image, region: CropRegion(x: 0, y: 0.5, width: 1, height: 0.5))
        XCTAssertNotNil(cropped)
        let color = centerColor(of: cropped!)
        XCTAssertNotNil(color)
        XCTAssertGreaterThan(color!.blueComponent, 0.5, "Bottom-half crop should be blue")
        XCTAssertLessThan(color!.redComponent, 0.5)
    }

    func testDegenerateRegionReturnsNil() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 100)
        // width * 100 == 0.5px, below the 1px guard.
        let result = view.applyCropToImage(image, region: CropRegion(x: 0, y: 0, width: 0.005, height: 0.5))
        XCTAssertNil(result)
    }
}

// MARK: - Straighten Transform Tests

final class StraightenTransformTests: XCTestCase {
    func testZeroAngleReturnsImageUnchanged() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 100)
        let result = view.applyStraightenTransform(angle: 0, to: image)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(result?.size.height ?? 0, 100, accuracy: 0.001)
    }

    func testNonZeroAngleAutoCropsSmaller() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 100)
        let result = view.applyStraightenTransform(angle: 8, to: image)
        XCTAssertNotNil(result)
        // Rotating and cropping to the largest inscribed axis-aligned rect shrinks it.
        XCTAssertLessThan(result?.size.width ?? 100, 100)
        XCTAssertGreaterThan(result?.size.width ?? 0, 0)
        XCTAssertLessThan(result?.size.height ?? 100, 100)
        XCTAssertGreaterThan(result?.size.height ?? 0, 0)
    }
}

// MARK: - Vignette Transform Tests

final class VignetteTransformTests: XCTestCase {
    func testVignettePreservesSize() {
        let view = SlideshowView()
        let image = makeSolidImage(size: 64)
        let result = view.applyVignette(intensity: 1.0, to: image)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width ?? 0, 64, accuracy: 0.001)
        XCTAssertEqual(result?.size.height ?? 0, 64, accuracy: 0.001)
    }

    func testVignetteReturnsNilForEmptyImage() {
        let view = SlideshowView()
        let result = view.applyVignette(intensity: 1.0, to: NSImage(size: .zero))
        XCTAssertNil(result)
    }
}
