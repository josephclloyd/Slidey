import SwiftUI
import AppKit
import CoreImage

// MARK: - Mouse event catcher for brush painting

class BrushCatcherView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    var onScrollWheel: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self, userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event.deltaY)
    }

    override func magnify(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

struct BrushOverlayCatcher: NSViewRepresentable {
    var onMouseDown: (CGPoint) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void
    var onMouseMoved: (CGPoint) -> Void
    var onMouseExited: () -> Void
    var onScrollWheel: (CGFloat) -> Void

    func makeNSView(context: Context) -> BrushCatcherView {
        let view = BrushCatcherView()
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        view.onMouseMoved = onMouseMoved
        view.onMouseExited = onMouseExited
        view.onScrollWheel = onScrollWheel
        return view
    }

    func updateNSView(_ nsView: BrushCatcherView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseDragged = onMouseDragged
        nsView.onMouseUp = onMouseUp
        nsView.onMouseMoved = onMouseMoved
        nsView.onMouseExited = onMouseExited
        nsView.onScrollWheel = onScrollWheel
    }
}

// MARK: - SlideshowView integration

extension SlideshowView {

    // MARK: - Overlay

    @ViewBuilder var localAdjustmentsOverlay: some View {
        if showLocalAdjustmentsHUD {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    BrushOverlayCatcher(
                        onMouseDown: { handleBrushMouseDown($0, containerSize: size) },
                        onMouseDragged: { handleBrushMouseDragged($0, containerSize: size) },
                        onMouseUp: { handleBrushMouseUp($0, containerSize: size) },
                        onMouseMoved: { localAdjController.mousePosition = $0 },
                        onMouseExited: { localAdjController.mousePosition = nil },
                        onScrollWheel: { handleBrushScrollWheel($0) }
                    )

                    brushCursorOverlay(containerSize: size)
                        .allowsHitTesting(false)
                }
            }
            localAdjustmentsHUDPanel
        }
    }

    @ViewBuilder private func brushCursorOverlay(containerSize: CGSize) -> some View {
        if let pos = localAdjController.mousePosition {
            let screenRadius = brushScreenRadius(containerSize: containerSize)
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: screenRadius * 2, height: screenRadius * 2)
                .position(pos)
        }
    }

    // MARK: - HUD panel

    @ViewBuilder private var localAdjustmentsHUDPanel: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text("Local Adjustments")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Spacer()
                    if let url = imageLoader.currentImageURL,
                       let layers = localAdjustmentURLLayers[url.absoluteString],
                       !layers.isEmpty {
                        Text("\(layers.count) layer\(layers.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                localAdjBrushRow

                localAdjRow("Exposure", value: localAdjExposureBinding, range: -2...2)
                localAdjRow("Highlights", value: localAdjHighlightsBinding, range: -1...1)
                localAdjRow("Shadows", value: localAdjShadowsBinding, range: -1...1)
                localAdjRow("Vibrance", value: localAdjVibranceBinding, range: -1...1)
                localAdjRow("Warmth", value: localAdjWarmthBinding, range: -1...1)

                HStack(spacing: 16) {
                    Button("Done") { closeLocalAdjustmentsHUD() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Spacer()
                    Button("Cancel") { cancelLocalAdjustmentsHUD() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Commit Layer") { commitLocalAdjustmentLayer() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!localAdjController.hasPainted)
                }

                Text("Paint mask, adjust sliders, commit. ⏎ commit · Esc cancel · [ ] brush size")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(20)
            .background(.black.opacity(0.85))
            .cornerRadius(12)
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private var localAdjBrushRow: some View {
        HStack {
            Text("Brush")
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            @Bindable var ctrl = localAdjController
            Slider(value: $ctrl.brushRadius, in: 5...200)
                .tint(.white)
            Text("\(Int(localAdjController.brushRadius))")
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func localAdjRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in scheduleLocalAdjPreview() }
                .tint(.white)
            Text(String(format: "%+.2f", value.wrappedValue))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Bindings for adjustment sliders

    private var localAdjExposureBinding: Binding<Double> {
        Binding(get: { localAdjController.adjustments.exposure },
                set: { localAdjController.adjustments.exposure = $0 })
    }

    private var localAdjHighlightsBinding: Binding<Double> {
        Binding(get: { localAdjController.adjustments.highlights },
                set: { localAdjController.adjustments.highlights = $0 })
    }

    private var localAdjShadowsBinding: Binding<Double> {
        Binding(get: { localAdjController.adjustments.shadows },
                set: { localAdjController.adjustments.shadows = $0 })
    }

    private var localAdjVibranceBinding: Binding<Double> {
        Binding(get: { localAdjController.adjustments.vibrance },
                set: { localAdjController.adjustments.vibrance = $0 })
    }

    private var localAdjWarmthBinding: Binding<Double> {
        Binding(get: { localAdjController.adjustments.warmth },
                set: { localAdjController.adjustments.warmth = $0 })
    }

    // MARK: - Open / Cancel / Commit / Close

    func openLocalAdjustmentsHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying,
              !showDenoiseHUD, !showVignetteHUD, !showAdjustmentsHUD,
              !showCurvesHUD, !showStraightenHUD, !showPerspectiveHUD,
              !showObjectRemovalHUD, !cropController.isActive else { return }

        showLocalAdjustmentsHUD = true
        updateDisplayImage()
        localAdjBaseImage = currentDisplayImage

        guard let base = localAdjBaseImage,
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        localAdjController.isActive = true
        localAdjController.initMask(width: cg.width, height: cg.height)
    }

    func cancelLocalAdjustmentsHUD() {
        guard showLocalAdjustmentsHUD else { return }
        showLocalAdjustmentsHUD = false
        localAdjPreviewTask?.cancel()
        localAdjPreviewTask = nil
        localAdjBaseImage = nil
        localAdjController.reset()
        updateDisplayImage()
    }

    func commitLocalAdjustmentLayer() {
        guard let url = imageLoader.currentImageURL,
              localAdjController.hasPainted,
              !localAdjController.adjustments.isIdentity,
              let maskData = localAdjController.extractMaskData() else {
            if localAdjController.hasPainted && localAdjController.adjustments.isIdentity {
                showLocalAdjToast("Adjust sliders before committing")
            }
            return
        }

        let layer = LocalAdjustmentLayer(
            maskData: maskData,
            maskWidth: localAdjController.maskWidth,
            maskHeight: localAdjController.maskHeight,
            adjustments: localAdjController.adjustments
        )

        let key = url.absoluteString
        var layers = localAdjustmentURLLayers[key] ?? []
        layers.append(layer)
        localAdjustmentURLLayers[key] = layers

        localAdjController.resetMask()
        updateDisplayImage()
        localAdjBaseImage = currentDisplayImage

        guard let base = localAdjBaseImage,
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        localAdjController.initMask(width: cg.width, height: cg.height)

        showLocalAdjToast("Layer committed (\(layers.count) total)")
    }

    func closeLocalAdjustmentsHUD() {
        if localAdjController.hasPainted && !localAdjController.adjustments.isIdentity {
            commitLocalAdjustmentLayer()
        }
        showLocalAdjustmentsHUD = false
        localAdjPreviewTask?.cancel()
        localAdjPreviewTask = nil
        localAdjBaseImage = nil
        localAdjController.reset()
        saveFavourites()
        updateDisplayImage()
    }

    func removeLocalAdjustmentsForCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        if showLocalAdjustmentsHUD { cancelLocalAdjustmentsHUD() }
        localAdjustmentURLLayers.removeValue(forKey: url.absoluteString)
        saveFavourites()
        updateDisplayImage()
    }

    // MARK: - Preview

    func scheduleLocalAdjPreview() {
        localAdjPreviewTask?.cancel()
        localAdjPreviewTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyLocalAdjPreview() }
        }
    }

    private func applyLocalAdjPreview() {
        guard let base = localAdjBaseImage else { return }

        guard localAdjController.hasPainted,
              let maskCG = localAdjController.maskCGImage() else {
            currentDisplayImage = base
            return
        }

        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            currentDisplayImage = base
            return
        }

        let ciBase = CIImage(cgImage: baseCG)
        let maskCI = CIImage(cgImage: maskCG)
        let scaleX = ciBase.extent.width / maskCI.extent.width
        let scaleY = ciBase.extent.height / maskCI.extent.height
        let scaledMask = (scaleX == 1 && scaleY == 1)
            ? maskCI
            : maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        if localAdjController.adjustments.isIdentity {
            let tint = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0))
                .cropped(to: ciBase.extent)
            guard let blend = CIFilter(name: "CIBlendWithMask") else {
                currentDisplayImage = base
                return
            }
            let overlay = tint.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.25)
            ])
            let composed = overlay.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: ciBase
            ])
            blend.setValue(composed, forKey: kCIInputImageKey)
            blend.setValue(ciBase, forKey: kCIInputBackgroundImageKey)
            blend.setValue(scaledMask, forKey: "inputMaskImage")
            if let output = blend.outputImage {
                let ctx = CIContext()
                if let outCG = ctx.createCGImage(output, from: output.extent) {
                    currentDisplayImage = NSImage(cgImage: outCG, size: base.size)
                    return
                }
            }
            currentDisplayImage = base
            return
        }

        guard let adjustedNS = applyAdjustments(localAdjController.adjustments, to: base),
              let adjustedCG = adjustedNS.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            currentDisplayImage = base
            return
        }
        let ciAdjusted = CIImage(cgImage: adjustedCG)

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            currentDisplayImage = base
            return
        }
        blend.setValue(ciAdjusted, forKey: kCIInputImageKey)
        blend.setValue(ciBase, forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaledMask, forKey: "inputMaskImage")

        if let output = blend.outputImage {
            let ctx = CIContext()
            if let outCG = ctx.createCGImage(output, from: output.extent) {
                currentDisplayImage = NSImage(cgImage: outCG, size: base.size)
                return
            }
        }
        currentDisplayImage = base
    }

    // MARK: - Compositing committed layers

    func applyLocalAdjustmentLayers(_ layers: [LocalAdjustmentLayer], to image: NSImage) -> NSImage? {
        guard !layers.isEmpty,
              let baseCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var ciCurrent = CIImage(cgImage: baseCG)
        let ctx = CIContext()

        for layer in layers {
            guard !layer.adjustments.isIdentity,
                  let maskCI = layer.maskCIImage() else { continue }

            let scaleX = ciCurrent.extent.width / maskCI.extent.width
            let scaleY = ciCurrent.extent.height / maskCI.extent.height
            let scaledMask = (scaleX == 1 && scaleY == 1)
                ? maskCI
                : maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            guard let currentCG = ctx.createCGImage(ciCurrent, from: ciCurrent.extent) else { continue }
            let currentNS = NSImage(cgImage: currentCG, size: image.size)
            guard let adjustedNS = applyAdjustments(layer.adjustments, to: currentNS),
                  let adjustedCG = adjustedNS.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let ciAdjusted = CIImage(cgImage: adjustedCG)

            guard let blend = CIFilter(name: "CIBlendWithMask") else { continue }
            blend.setValue(ciAdjusted, forKey: kCIInputImageKey)
            blend.setValue(ciCurrent, forKey: kCIInputBackgroundImageKey)
            blend.setValue(scaledMask, forKey: "inputMaskImage")

            if let output = blend.outputImage {
                ciCurrent = output
            }
        }

        guard let outCG = ctx.createCGImage(ciCurrent, from: ciCurrent.extent) else { return nil }
        return NSImage(cgImage: outCG, size: image.size)
    }

    // MARK: - Mouse event handlers

    private func handleBrushMouseDown(_ point: CGPoint, containerSize: CGSize) {
        guard let pixel = viewToImagePixel(point, containerSize: containerSize) else { return }
        let pixelRadius = brushPixelRadius(containerSize: containerSize)
        localAdjController.paintDab(at: pixel, pixelRadius: pixelRadius)
        localAdjController.hasPainted = true
        localAdjController.lastPaintPixel = pixel
        localAdjController.maskVersion += 1
        scheduleLocalAdjPreview()
    }

    private func handleBrushMouseDragged(_ point: CGPoint, containerSize: CGSize) {
        localAdjController.mousePosition = point
        guard let pixel = viewToImagePixel(point, containerSize: containerSize) else { return }
        let pixelRadius = brushPixelRadius(containerSize: containerSize)
        if let last = localAdjController.lastPaintPixel {
            localAdjController.paintStroke(from: last, to: pixel, pixelRadius: pixelRadius)
        } else {
            localAdjController.paintDab(at: pixel, pixelRadius: pixelRadius)
            localAdjController.hasPainted = true
            localAdjController.maskVersion += 1
        }
        localAdjController.lastPaintPixel = pixel
        scheduleLocalAdjPreview()
    }

    private func handleBrushMouseUp(_ point: CGPoint, containerSize: CGSize) {
        localAdjController.lastPaintPixel = nil
    }

    private func handleBrushScrollWheel(_ deltaY: CGFloat) {
        localAdjController.brushRadius = max(5, min(200, localAdjController.brushRadius + deltaY * 2))
    }

    // MARK: - Coordinate conversion

    private func viewToImagePixel(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = brushFittedSize(containerSize: containerSize) else { return nil }
        let norm = CropController.viewToNormalized(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
        let px = norm.x * CGFloat(localAdjController.maskWidth)
        let py = norm.y * CGFloat(localAdjController.maskHeight)
        return CGPoint(x: px, y: py)
    }

    private func brushFittedSize(containerSize: CGSize) -> CGSize? {
        guard let base = localAdjBaseImage,
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CropController.fittedImageSize(
            imagePixelSize: CGSize(width: cg.width, height: cg.height),
            containerSize: containerSize,
            rotationAngle: rotationAngle
        )
    }

    private func brushPixelRadius(containerSize: CGSize) -> CGFloat {
        guard let fitted = brushFittedSize(containerSize: containerSize),
              fitted.width > 0 else { return localAdjController.brushRadius }
        let viewToPixel = CGFloat(localAdjController.maskWidth) / (fitted.width * zoomPan.zoomScale)
        return localAdjController.brushRadius * viewToPixel
    }

    func brushScreenRadius(containerSize: CGSize) -> CGFloat {
        localAdjController.brushRadius
    }

    // MARK: - Toast helper

    private func showLocalAdjToast(_ message: String) {
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }
}
