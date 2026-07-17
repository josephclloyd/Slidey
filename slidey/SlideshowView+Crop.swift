import SwiftUI
import AppKit
import CoreImage

// MARK: - Mouse event catcher for crop mode

class CropCatcherView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

struct CropOverlayCatcher: NSViewRepresentable {
    var onMouseDown: (CGPoint) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void

    func makeNSView(context: Context) -> CropCatcherView {
        let view = CropCatcherView()
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        return view
    }

    func updateNSView(_ nsView: CropCatcherView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseDragged = onMouseDragged
        nsView.onMouseUp = onMouseUp
    }
}

// MARK: - Crop overlay + SlideshowView integration

extension SlideshowView {

    // MARK: - Overlay view

    @ViewBuilder var cropOverlay: some View {
        if cropController.isActive {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    CropOverlayCatcher(
                        onMouseDown: { handleCropMouseDown($0, containerSize: size) },
                        onMouseDragged: { handleCropMouseDragged($0, containerSize: size) },
                        onMouseUp: { handleCropMouseUp($0, containerSize: size) }
                    )

                    cropVisual(containerSize: size)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Crop region")
                .accessibilityValue(cropAccessibilityValue)
                .accessibilityHint("Adjust to resize the crop region. Apply or cancel using the actions.")
                .accessibilityAction(named: "Apply crop") { confirmCrop() }
                .accessibilityAction(named: "Cancel crop") { cancelCrop() }
                .accessibilityAdjustableAction { adjustCropRegionForAccessibility($0) }
            }
        }
    }

    private var cropAccessibilityValue: String {
        guard let region = cropController.pendingRegion else {
            return "No crop region defined. Drag on the image to define one."
        }
        let widthPct = Int((region.width * 100).rounded())
        let heightPct = Int((region.height * 100).rounded())
        return "\(widthPct) percent wide by \(heightPct) percent tall"
    }

    private func adjustCropRegionForAccessibility(_ direction: AccessibilityAdjustmentDirection) {
        guard var region = cropController.pendingRegion else { return }
        let delta: Double = direction == .increment ? 0.05 : -0.05
        let centerX = region.x + region.width / 2
        let centerY = region.y + region.height / 2
        let newWidth = min(max(region.width + delta, 0.05), 1.0)
        let newHeight = min(max(region.height + delta, 0.05), 1.0)
        region.width = newWidth
        region.height = newHeight
        region.x = min(max(centerX - newWidth / 2, 0), 1 - newWidth)
        region.y = min(max(centerY - newHeight / 2, 0), 1 - newHeight)
        if region.isValid { cropController.pendingRegion = region }
    }

    @ViewBuilder private func cropVisual(containerSize: CGSize) -> some View {
        if let region = cropController.displayRegion,
           let viewRect = cropRectInView(region: region, containerSize: containerSize) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: containerSize))
                p.addRect(viewRect)
            }
            .fill(style: FillStyle(eoFill: true))
            .foregroundColor(.black.opacity(0.5))

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: viewRect.width, height: viewRect.height)
                .position(x: viewRect.midX, y: viewRect.midY)

            // Rule-of-thirds grid
            let thirdW = viewRect.width / 3
            let thirdH = viewRect.height / 3
            Path { p in
                for i in 1...2 {
                    let x = viewRect.minX + thirdW * CGFloat(i)
                    p.move(to: CGPoint(x: x, y: viewRect.minY))
                    p.addLine(to: CGPoint(x: x, y: viewRect.maxY))
                    let y = viewRect.minY + thirdH * CGFloat(i)
                    p.move(to: CGPoint(x: viewRect.minX, y: y))
                    p.addLine(to: CGPoint(x: viewRect.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)

            if cropController.pendingRegion != nil {
                ForEach(Array(cropController.handlePositions().enumerated()), id: \.offset) { _, item in
                    if let viewPos = normalizedToView(item.1, containerSize: containerSize) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .position(viewPos)
                    }
                }
            }

            VStack {
                Spacer()
                Text("Return to apply \u{2022} Escape to cancel")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.7))
                    .cornerRadius(6)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Coordinate helpers

    private func cropFittedSize(containerSize: CGSize) -> CGSize? {
        guard let image = effectiveDisplayImage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CropController.fittedImageSize(
            imagePixelSize: CGSize(width: cg.width, height: cg.height),
            containerSize: containerSize,
            rotationAngle: rotationAngle
        )
    }

    private func viewToNormalized(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = cropFittedSize(containerSize: containerSize) else { return nil }
        return CropController.viewToNormalized(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
    }

    private func normalizedToView(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = cropFittedSize(containerSize: containerSize) else { return nil }
        return CropController.normalizedToView(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
    }

    private func cropRectInView(region: CropRegion, containerSize: CGSize) -> CGRect? {
        let corners = [
            CGPoint(x: region.x, y: region.y),
            CGPoint(x: region.x + region.width, y: region.y),
            CGPoint(x: region.x, y: region.y + region.height),
            CGPoint(x: region.x + region.width, y: region.y + region.height),
        ]
        let viewCorners = corners.compactMap { normalizedToView($0, containerSize: containerSize) }
        guard viewCorners.count == 4 else { return nil }
        let xs = viewCorners.map(\.x)
        let ys = viewCorners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func hitTestHandle(at viewPoint: CGPoint, containerSize: CGSize) -> CropController.Handle? {
        let hitRadius: CGFloat = 12
        for (handle, normalizedPos) in cropController.handlePositions() {
            guard let viewPos = normalizedToView(normalizedPos, containerSize: containerSize) else { continue }
            if hypot(viewPoint.x - viewPos.x, viewPoint.y - viewPos.y) <= hitRadius {
                return handle
            }
        }
        return nil
    }

    // MARK: - Mouse event handlers

    private func handleCropMouseDown(_ point: CGPoint, containerSize: CGSize) {
        guard let normalized = viewToNormalized(point, containerSize: containerSize) else { return }

        if let handle = hitTestHandle(at: point, containerSize: containerSize) {
            cropController.activeHandle = handle
            cropController.isDragging = true
            cropController.regionBeforeDrag = cropController.pendingRegion
            cropController.dragStartNormalized = normalized
            cropController.dragCurrentNormalized = normalized
            return
        }

        cropController.pendingRegion = nil
        cropController.activeHandle = nil
        cropController.isDragging = true
        cropController.dragStartNormalized = normalized
        cropController.dragCurrentNormalized = normalized
    }

    private func handleCropMouseDragged(_ point: CGPoint, containerSize: CGSize) {
        guard cropController.isDragging else { return }
        guard var normalized = viewToNormalized(point, containerSize: containerSize) else { return }

        if NSEvent.modifierFlags.contains(.shift),
           cropController.activeHandle == nil,
           let start = cropController.dragStartNormalized,
           let image = effectiveDisplayImage,
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ar = CGFloat(cg.width) / CGFloat(cg.height)
            normalized = CropController.constrainToAspectRatio(start: start, end: normalized, aspectRatio: ar)
        }

        cropController.dragCurrentNormalized = normalized

        if let handle = cropController.activeHandle {
            cropController.applyHandleDrag(handle: handle, to: normalized)
        }
    }

    private func handleCropMouseUp(_ point: CGPoint, containerSize: CGSize) {
        guard cropController.isDragging else { return }
        guard var normalized = viewToNormalized(point, containerSize: containerSize) else { return }

        cropController.isDragging = false

        if cropController.activeHandle != nil {
            cropController.activeHandle = nil
            cropController.regionBeforeDrag = nil
        } else if let start = cropController.dragStartNormalized {
            if NSEvent.modifierFlags.contains(.shift),
               let image = effectiveDisplayImage,
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ar = CGFloat(cg.width) / CGFloat(cg.height)
                normalized = CropController.constrainToAspectRatio(start: start, end: normalized, aspectRatio: ar)
            }
            let region = CropRegion.fromPoints(start, normalized)
            if region.isValid {
                cropController.pendingRegion = region
            }
        }
        cropController.dragStartNormalized = nil
        cropController.dragCurrentNormalized = nil
    }

    // MARK: - Actions

    func enterCropMode() {
        guard !showDenoiseHUD, !showVignetteHUD, !showAdjustmentsHUD, !showPerspectiveHUD, !showLocalAdjustmentsHUD, !showObjectRemovalHUD else { return }
        guard imageLoader.currentImageURL != nil else { return }

        if cropController.isActive {
            cancelCrop()
            return
        }

        cropController.isActive = true
        if let url = imageLoader.currentImageURL,
           let existing = cropRegions[url.absoluteString] {
            cropController.pendingRegion = existing
        }
    }

    func cancelCrop() {
        cropController.reset()
    }

    func confirmCrop() {
        guard let url = imageLoader.currentImageURL,
              let region = cropController.pendingRegion,
              region.isValid else {
            cancelCrop()
            return
        }
        registerUndoForEdit(url: url, actionName: "Crop")
        cropRegions[url.absoluteString] = region
        saveFavourites()
        cropController.reset()
        updateDisplayImage()
    }

    func removeCropForCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        registerUndoForEdit(url: url, actionName: "Remove Crop")
        if cropController.isActive { cropController.reset() }
        cropRegions.removeValue(forKey: url.absoluteString)
        saveFavourites()
        updateDisplayImage()
    }

    func applyCropToImage(_ image: NSImage, region: CropRegion) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let w = ciImage.extent.width
        let h = ciImage.extent.height
        // Normalized rect uses top-left origin; CIImage uses bottom-left
        let cropRect = CGRect(
            x: region.x * w,
            y: (1 - region.y - region.height) * h,
            width: region.width * w,
            height: region.height * h
        )
        guard cropRect.width > 1, cropRect.height > 1 else { return nil }
        let cropped = ciImage.cropped(to: cropRect)
        let translated = cropped.transformed(by: CGAffineTransform(
            translationX: -cropRect.origin.x, y: -cropRect.origin.y
        ))
        let context = CIContext()
        guard let cgOut = context.createCGImage(translated, from: translated.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: NSSize(width: cgOut.width, height: cgOut.height))
    }
}
