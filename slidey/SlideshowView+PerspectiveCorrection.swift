import SwiftUI
import AppKit
import CoreImage
import Vision

struct PerspectiveCorners: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    static let identity = PerspectiveCorners(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 1, y: 0),
        bottomLeft: CGPoint(x: 0, y: 1),
        bottomRight: CGPoint(x: 1, y: 1)
    )

    subscript(index: Int) -> CGPoint {
        get {
            switch index {
            case 0: return topLeft
            case 1: return topRight
            case 2: return bottomLeft
            case 3: return bottomRight
            default: return .zero
            }
        }
        set {
            switch index {
            case 0: topLeft = newValue
            case 1: topRight = newValue
            case 2: bottomLeft = newValue
            case 3: bottomRight = newValue
            default: break
            }
        }
    }
}

// MARK: - Mouse event catcher for perspective mode

class PerspectiveCatcherView: NSView {
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

struct PerspectiveOverlayCatcher: NSViewRepresentable {
    var onMouseDown: (CGPoint) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void

    func makeNSView(context: Context) -> PerspectiveCatcherView {
        let view = PerspectiveCatcherView()
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        return view
    }

    func updateNSView(_ nsView: PerspectiveCatcherView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseDragged = onMouseDragged
        nsView.onMouseUp = onMouseUp
    }
}

// MARK: - SlideshowView integration

extension SlideshowView {

    @ViewBuilder var perspectiveCorrectionOverlay: some View {
        if showPerspectiveHUD, let corners = perspectiveHUDCorners {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    PerspectiveOverlayCatcher(
                        onMouseDown: { handlePerspectiveMouseDown($0, containerSize: size) },
                        onMouseDragged: { handlePerspectiveMouseDragged($0, containerSize: size) },
                        onMouseUp: { handlePerspectiveMouseUp($0, containerSize: size) }
                    )

                    perspectiveVisual(corners: corners, containerSize: size)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder private func perspectiveVisual(corners: PerspectiveCorners, containerSize: CGSize) -> some View {
        let viewPts = (0..<4).compactMap { perspectiveNormalizedToView(corners[$0], containerSize: containerSize) }
        if viewPts.count == 4 {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: containerSize))
                p.move(to: viewPts[0])
                p.addLine(to: viewPts[1])
                p.addLine(to: viewPts[3])
                p.addLine(to: viewPts[2])
                p.closeSubpath()
            }
            .fill(style: FillStyle(eoFill: true))
            .foregroundColor(.black.opacity(0.5))

            Path { p in
                p.move(to: viewPts[0])
                p.addLine(to: viewPts[1])
                p.addLine(to: viewPts[3])
                p.addLine(to: viewPts[2])
                p.closeSubpath()
            }
            .stroke(Color.white, lineWidth: 2)

            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .position(viewPts[i])
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

    private func perspectiveFittedSize(containerSize: CGSize) -> CGSize? {
        guard let image = effectiveDisplayImage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CropController.fittedImageSize(
            imagePixelSize: CGSize(width: cg.width, height: cg.height),
            containerSize: containerSize,
            rotationAngle: rotationAngle
        )
    }

    private func perspectiveViewToNormalized(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = perspectiveFittedSize(containerSize: containerSize) else { return nil }
        return CropController.viewToNormalized(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
    }

    private func perspectiveNormalizedToView(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = perspectiveFittedSize(containerSize: containerSize) else { return nil }
        return CropController.normalizedToView(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
    }

    // MARK: - Mouse event handlers

    private func handlePerspectiveMouseDown(_ point: CGPoint, containerSize: CGSize) {
        guard let corners = perspectiveHUDCorners else { return }
        let hitRadius: CGFloat = 14
        for i in 0..<4 {
            guard let viewPos = perspectiveNormalizedToView(corners[i], containerSize: containerSize) else { continue }
            if hypot(point.x - viewPos.x, point.y - viewPos.y) <= hitRadius {
                perspectiveDraggingCorner = i
                return
            }
        }
    }

    private func handlePerspectiveMouseDragged(_ point: CGPoint, containerSize: CGSize) {
        guard let dragging = perspectiveDraggingCorner,
              var corners = perspectiveHUDCorners,
              let normalized = perspectiveViewToNormalized(point, containerSize: containerSize) else { return }
        let clamped = CGPoint(x: max(0, min(1, normalized.x)), y: max(0, min(1, normalized.y)))
        corners[dragging] = clamped
        perspectiveHUDCorners = corners
    }

    private func handlePerspectiveMouseUp(_ point: CGPoint, containerSize: CGSize) {
        perspectiveDraggingCorner = nil
    }

    // MARK: - Actions

    func openPerspectiveHUD() {
        guard let url = imageLoader.currentImageURL else { return }
        guard let image = imageLoader.currentImage else { return }
        guard !slideshow.isPlaying else { return }
        guard !cropController.isActive, !showStraightenHUD, !showDenoiseHUD,
              !showVignetteHUD, !showAdjustmentsHUD, !showCurvesHUD else { return }

        if let existing = perspectiveCorners[url.absoluteString] {
            perspectiveHUDCorners = existing
            showPerspectiveHUD = true
            return
        }

        showPerspectiveHUD = true
        perspectiveHUDCorners = .identity

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let request = VNDetectRectanglesRequest { request, _ in
            guard let results = request.results as? [VNRectangleObservation],
                  let best = results.first, best.confidence > 0.5 else { return }
            let detected = PerspectiveCorners(
                topLeft: CGPoint(x: best.topLeft.x, y: 1 - best.topLeft.y),
                topRight: CGPoint(x: best.topRight.x, y: 1 - best.topRight.y),
                bottomLeft: CGPoint(x: best.bottomLeft.x, y: 1 - best.bottomLeft.y),
                bottomRight: CGPoint(x: best.bottomRight.x, y: 1 - best.bottomRight.y)
            )
            DispatchQueue.main.async {
                guard self.showPerspectiveHUD,
                      self.imageLoader.currentImageURL == url else { return }
                self.perspectiveHUDCorners = detected
            }
        }
        request.maximumObservations = 1
        request.minimumConfidence = 0.3

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func cancelPerspectiveHUD() {
        showPerspectiveHUD = false
        perspectiveHUDCorners = nil
        perspectiveDraggingCorner = nil
    }

    func applyPerspectiveToImage() {
        guard let url = imageLoader.currentImageURL,
              let corners = perspectiveHUDCorners else {
            cancelPerspectiveHUD()
            return
        }
        if corners == .identity {
            perspectiveCorners.removeValue(forKey: url.absoluteString)
        } else {
            perspectiveCorners[url.absoluteString] = corners
        }
        saveFavourites()
        showPerspectiveHUD = false
        perspectiveHUDCorners = nil
        perspectiveDraggingCorner = nil
        updateDisplayImage()
    }

    func removePerspectiveCorrectionForCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        if showPerspectiveHUD { cancelPerspectiveHUD() }
        perspectiveCorners.removeValue(forKey: url.absoluteString)
        saveFavourites()
        updateDisplayImage()
    }

    func applyPerspectiveTransform(corners: PerspectiveCorners, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let w = ciImage.extent.width
        let h = ciImage.extent.height

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: corners.topLeft.x * w, y: (1 - corners.topLeft.y) * h),
                        forKey: "inputTopLeft")
        filter.setValue(CIVector(x: corners.topRight.x * w, y: (1 - corners.topRight.y) * h),
                        forKey: "inputTopRight")
        filter.setValue(CIVector(x: corners.bottomLeft.x * w, y: (1 - corners.bottomLeft.y) * h),
                        forKey: "inputBottomLeft")
        filter.setValue(CIVector(x: corners.bottomRight.x * w, y: (1 - corners.bottomRight.y) * h),
                        forKey: "inputBottomRight")

        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgOut = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: NSSize(width: cgOut.width, height: cgOut.height))
    }
}
