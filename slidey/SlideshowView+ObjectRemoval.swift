import SwiftUI
import AppKit
import CoreImage
import CoreML

@Observable
final class ObjectRemovalController {
    var isActive = false
    var brushRadius: Double = 40
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
        ctx.saveGState()
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setBlendMode(.normal)
        let rect = CGRect(
            x: center.x - pixelRadius,
            y: center.y - pixelRadius,
            width: pixelRadius * 2,
            height: pixelRadius * 2
        )
        ctx.fillEllipse(in: rect)
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

    func reset() {
        isActive = false
        maskContext = nil
        maskWidth = 0
        maskHeight = 0
        mousePosition = nil
        lastPaintPixel = nil
        hasPainted = false
        maskVersion = 0
    }
}

// MARK: - SlideshowView integration

extension SlideshowView {

    // MARK: - Overlay

    @ViewBuilder var objectRemovalOverlay: some View {
        if showObjectRemovalHUD {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    BrushOverlayCatcher(
                        onMouseDown: { handleObjectRemovalMouseDown($0, containerSize: size) },
                        onMouseDragged: { handleObjectRemovalMouseDragged($0, containerSize: size) },
                        onMouseUp: { handleObjectRemovalMouseUp($0, containerSize: size) },
                        onMouseMoved: { objectRemovalController.mousePosition = $0 },
                        onMouseExited: { objectRemovalController.mousePosition = nil },
                        onScrollWheel: { handleObjectRemovalScrollWheel($0) }
                    )

                    objectRemovalBrushCursor(containerSize: size)
                        .allowsHitTesting(false)

                    objectRemovalMaskPreview(containerSize: size)
                        .allowsHitTesting(false)
                }
            }
            objectRemovalHUDPanel
        }
    }

    @ViewBuilder private func objectRemovalBrushCursor(containerSize: CGSize) -> some View {
        if let pos = objectRemovalController.mousePosition {
            let screenRadius = objectRemovalController.brushRadius
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: screenRadius * 2, height: screenRadius * 2)
                .position(pos)
        }
    }

    @ViewBuilder private func objectRemovalMaskPreview(containerSize: CGSize) -> some View {
        let _ = objectRemovalController.maskVersion
        if objectRemovalController.hasPainted,
           let maskCG = objectRemovalController.maskCGImage(),
           let fitted = objectRemovalFittedSize(containerSize: containerSize) {
            let scaledW = fitted.width * zoomPan.zoomScale
            let scaledH = fitted.height * zoomPan.zoomScale
            let centerX = containerSize.width / 2 + zoomPan.imageOffset.width
            let centerY = containerSize.height / 2 + zoomPan.imageOffset.height
            Image(decorative: maskCG, scale: 1.0)
                .resizable()
                .frame(width: scaledW, height: scaledH)
                .position(x: centerX, y: centerY)
                .rotationEffect(rotationAngle)
                .colorMultiply(.red)
                .opacity(0.4)
        }
    }

    // MARK: - HUD panel

    @ViewBuilder private var objectRemovalHUDPanel: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    Text("Remove Object")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Spacer()
                    if isInpainting {
                        Text("Processing\u{2026}")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if isInpainting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    objectRemovalBrushRow
                }

                HStack(spacing: 16) {
                    Button("Cancel") { cancelObjectRemovalHUD() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Spacer()
                    Button("Inpaint") { applyObjectRemoval() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!objectRemovalController.hasPainted || isInpainting)
                }

                Text("Paint over the object to remove, then click Inpaint. \u{23CE} apply \u{00B7} Esc cancel \u{00B7} [ ] brush size")
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

    private var objectRemovalBrushRow: some View {
        HStack {
            Text("Brush")
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            @Bindable var ctrl = objectRemovalController
            Slider(value: $ctrl.brushRadius, in: 5...200)
                .tint(.white)
            Text("\(Int(objectRemovalController.brushRadius))")
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Open / Cancel / Apply

    func openObjectRemovalHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying,
              !showDenoiseHUD, !showVignetteHUD, !showAdjustmentsHUD,
              !showCurvesHUD, !showStraightenHUD, !showPerspectiveHUD,
              !showLocalAdjustmentsHUD, !showJPEGCleanupHUD, !showGrainReductionHUD,
              !cropController.isActive, !showObjectRemovalHUD,
              !isInpainting else { return }

        showObjectRemovalHUD = true
        updateDisplayImage()
        objectRemovalBaseImage = currentDisplayImage

        guard let base = objectRemovalBaseImage,
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        objectRemovalController.isActive = true
        objectRemovalController.initMask(width: cg.width, height: cg.height)
    }

    func cancelObjectRemovalHUD() {
        guard showObjectRemovalHUD else { return }
        showObjectRemovalHUD = false
        isInpainting = false
        objectRemovalBaseImage = nil
        objectRemovalController.reset()
        updateDisplayImage()
    }

    // swiftlint:disable:next function_body_length
    func applyObjectRemoval() {
        guard !isInpainting, objectRemovalController.hasPainted else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let base = objectRemovalBaseImage,
              let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let maskCG = objectRemovalController.maskCGImage() else { return }

        isInpainting = true

        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelURL = Bundle.main.url(forResource: "LaMa_Inpainting", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "LaMa_Inpainting", withExtension: "mlpackage") else {
                DispatchQueue.main.async {
                    self.isInpainting = false
                    self.cancelObjectRemovalHUD()
                }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async {
                    self.isInpainting = false
                    self.cancelObjectRemovalHUD()
                }
                return
            }

            let modelSize = 512
            let imgW = baseCG.width, imgH = baseCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

            guard let imgCtx = CGContext(data: nil, width: imgW, height: imgH,
                                          bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                          space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isInpainting = false }
                return
            }
            imgCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let imgData = imgCtx.data else {
                DispatchQueue.main.async { self.isInpainting = false }
                return
            }
            let imgPixels = imgData.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

            let maskGrayCS = CGColorSpaceCreateDeviceGray()
            guard let maskCtx = CGContext(data: nil, width: imgW, height: imgH,
                                           bitsPerComponent: 8, bytesPerRow: imgW,
                                           space: maskGrayCS,
                                           bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                DispatchQueue.main.async { self.isInpainting = false }
                return
            }
            maskCtx.draw(maskCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let maskData = maskCtx.data else {
                DispatchQueue.main.async { self.isInpainting = false }
                return
            }
            let maskPixels = maskData.bindMemory(to: UInt8.self, capacity: imgW * imgH)

            guard let imgArr = try? MLMultiArray(shape: [1, 3, NSNumber(value: modelSize), NSNumber(value: modelSize)], dataType: .float32),
                  let maskArr = try? MLMultiArray(shape: [1, 1, NSNumber(value: modelSize), NSNumber(value: modelSize)], dataType: .float32) else {
                DispatchQueue.main.async { self.isInpainting = false }
                return
            }

            let planeSize = modelSize * modelSize
            imgArr.withUnsafeMutableBytes { buf, _ in
                let ptr = buf.bindMemory(to: Float.self)
                for row in 0..<modelSize {
                    let srcRow = row * imgH / modelSize
                    for col in 0..<modelSize {
                        let srcCol = col * imgW / modelSize
                        let srcIdx = srcRow * imgW + srcCol
                        let pos = row * modelSize + col
                        ptr[0 * planeSize + pos] = Float(imgPixels[srcIdx * 4 + 2]) / 255.0
                        ptr[1 * planeSize + pos] = Float(imgPixels[srcIdx * 4 + 1]) / 255.0
                        ptr[2 * planeSize + pos] = Float(imgPixels[srcIdx * 4 + 0]) / 255.0
                    }
                }
            }

            maskArr.withUnsafeMutableBytes { buf, _ in
                let ptr = buf.bindMemory(to: Float.self)
                for row in 0..<modelSize {
                    let srcRow = row * imgH / modelSize
                    for col in 0..<modelSize {
                        let srcCol = col * imgW / modelSize
                        let pos = row * modelSize + col
                        ptr[pos] = maskPixels[srcRow * imgW + srcCol] > 127 ? 1.0 : 0.0
                    }
                }
            }

            guard let features = try? MLDictionaryFeatureProvider(
                      dictionary: ["image": MLFeatureValue(multiArray: imgArr),
                                   "mask": MLFeatureValue(multiArray: maskArr)]),
                  let output = try? model.prediction(from: features),
                  let outArr = output.featureValue(for: "inpainted")?.multiArrayValue else {
                DispatchQueue.main.async {
                    self.isInpainting = false
                    self.cancelObjectRemovalHUD()
                }
                return
            }

            let isFP16 = outArr.dataType == .float16
            var outPixels = [UInt8](repeating: 255, count: imgW * imgH * 4)

            outArr.withUnsafeBytes { rawBuf in
                let ptr32 = isFP16 ? nil : rawBuf.bindMemory(to: Float.self)
                let ptr16 = isFP16 ? rawBuf.bindMemory(to: UInt16.self) : nil

                for row in 0..<imgH {
                    let mRow = row * modelSize / imgH
                    for col in 0..<imgW {
                        let mCol = col * modelSize / imgW
                        let mPos = mRow * modelSize + mCol
                        let pixIdx = row * imgW + col
                        let maskVal = maskPixels[pixIdx]

                        if maskVal > 127 {
                            let r: Float, g: Float, b: Float
                            if isFP16, let p = ptr16 {
                                r = Float(Float16(bitPattern: p[0 * planeSize + mPos]))
                                g = Float(Float16(bitPattern: p[1 * planeSize + mPos]))
                                b = Float(Float16(bitPattern: p[2 * planeSize + mPos]))
                            } else if let p = ptr32 {
                                r = p[0 * planeSize + mPos]
                                g = p[1 * planeSize + mPos]
                                b = p[2 * planeSize + mPos]
                            } else {
                                r = 0; g = 0; b = 0
                            }
                            let rByte = r.isFinite ? UInt8(min(255, max(0, Int(r * 255)))) : 0
                            let gByte = g.isFinite ? UInt8(min(255, max(0, Int(g * 255)))) : 0
                            let bByte = b.isFinite ? UInt8(min(255, max(0, Int(b * 255)))) : 0
                            outPixels[pixIdx * 4 + 0] = bByte
                            outPixels[pixIdx * 4 + 1] = gByte
                            outPixels[pixIdx * 4 + 2] = rByte
                            outPixels[pixIdx * 4 + 3] = 255
                        } else {
                            outPixels[pixIdx * 4 + 0] = imgPixels[pixIdx * 4 + 0]
                            outPixels[pixIdx * 4 + 1] = imgPixels[pixIdx * 4 + 1]
                            outPixels[pixIdx * 4 + 2] = imgPixels[pixIdx * 4 + 2]
                            outPixels[pixIdx * 4 + 3] = 255
                        }
                    }
                }
            }

            let capturedURL = url
            outPixels.withUnsafeMutableBytes { ptr in
                guard let outCtx = CGContext(data: ptr.baseAddress, width: imgW, height: imgH,
                                              bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                              space: cs, bitmapInfo: bi),
                      let outCG = outCtx.makeImage() else {
                    DispatchQueue.main.async { self.isInpainting = false }
                    return
                }
                let result = NSImage(cgImage: outCG, size: base.size)
                DispatchQueue.main.async {
                    self.objectRemovedImages[capturedURL] = result
                    self.clearCachesDownstream(of: .objectRemoval, for: capturedURL)
                    self.editStacks[capturedURL, default: EditStack()].append(.objectRemoval)
                    self.effectImages[capturedURL] = nil
                    self.isInpainting = false
                    self.showObjectRemovalHUD = false
                    self.objectRemovalBaseImage = nil
                    self.objectRemovalController.reset()
                    self.saveFavourites()
                    self.updateDisplayImage()
                }
            }
        }
    }

    func removeObjectRemovalForCurrentImage() {
        removeEdit(.objectRemoval)
    }

    // MARK: - Mouse event handlers

    private func handleObjectRemovalMouseDown(_ point: CGPoint, containerSize: CGSize) {
        guard !isInpainting else { return }
        guard let pixel = objectRemovalViewToImagePixel(point, containerSize: containerSize) else { return }
        let pixelRadius = objectRemovalBrushPixelRadius(containerSize: containerSize)
        objectRemovalController.paintDab(at: pixel, pixelRadius: pixelRadius)
        objectRemovalController.hasPainted = true
        objectRemovalController.lastPaintPixel = pixel
        objectRemovalController.maskVersion += 1
    }

    private func handleObjectRemovalMouseDragged(_ point: CGPoint, containerSize: CGSize) {
        guard !isInpainting else { return }
        objectRemovalController.mousePosition = point
        guard let pixel = objectRemovalViewToImagePixel(point, containerSize: containerSize) else { return }
        let pixelRadius = objectRemovalBrushPixelRadius(containerSize: containerSize)
        if let last = objectRemovalController.lastPaintPixel {
            objectRemovalController.paintStroke(from: last, to: pixel, pixelRadius: pixelRadius)
        } else {
            objectRemovalController.paintDab(at: pixel, pixelRadius: pixelRadius)
            objectRemovalController.hasPainted = true
            objectRemovalController.maskVersion += 1
        }
        objectRemovalController.lastPaintPixel = pixel
    }

    private func handleObjectRemovalMouseUp(_ point: CGPoint, containerSize: CGSize) {
        objectRemovalController.lastPaintPixel = nil
    }

    private func handleObjectRemovalScrollWheel(_ deltaY: CGFloat) {
        objectRemovalController.brushRadius = max(5, min(200, objectRemovalController.brushRadius + deltaY * 2))
    }

    // MARK: - Coordinate conversion

    private func objectRemovalViewToImagePixel(_ point: CGPoint, containerSize: CGSize) -> CGPoint? {
        guard let fitted = objectRemovalFittedSize(containerSize: containerSize) else { return nil }
        let norm = CropController.viewToNormalized(
            point: point, containerSize: containerSize, fittedSize: fitted,
            zoomScale: zoomPan.zoomScale, imageOffset: zoomPan.imageOffset,
            rotationAngle: rotationAngle
        )
        let px = norm.x * CGFloat(objectRemovalController.maskWidth)
        let py = norm.y * CGFloat(objectRemovalController.maskHeight)
        return CGPoint(x: px, y: py)
    }

    private func objectRemovalFittedSize(containerSize: CGSize) -> CGSize? {
        guard let base = objectRemovalBaseImage,
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CropController.fittedImageSize(
            imagePixelSize: CGSize(width: cg.width, height: cg.height),
            containerSize: containerSize,
            rotationAngle: rotationAngle
        )
    }

    private func objectRemovalBrushPixelRadius(containerSize: CGSize) -> CGFloat {
        guard let fitted = objectRemovalFittedSize(containerSize: containerSize),
              fitted.width > 0 else { return objectRemovalController.brushRadius }
        let viewToPixel = CGFloat(objectRemovalController.maskWidth) / (fitted.width * zoomPan.zoomScale)
        return objectRemovalController.brushRadius * viewToPixel
    }
}
