import SwiftUI
import AppKit
import CoreImage
import CoreML
import Vision

final class SwinIRCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; _cancelled = true }
}

extension SlideshowView {

    func removeFaceRestoration() {
        removeEdit(.faceRestore)
    }

    func removeRedEyeCorrection() {
        removeEdit(.redEyeRemoval)
    }

    func applyRedEyeOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = currentComposite(for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: srcCG, options: [:]).perform([req])
            guard let faces = req.results as? [VNFaceObservation], !faces.isEmpty else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            let ciImg = CIImage(cgImage: srcCG)
            guard let filter = CIFilter(name: "CIRedEyeCorrection") else { return }
            filter.setValue(ciImg, forKey: kCIInputImageKey)
            guard let output = filter.outputImage else { return }
            let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            guard let cgResult = ctx.createCGImage(output, from: output.extent) else { return }
            let result = NSImage(cgImage: cgResult, size: source.size)
            let capturedURL = url
            DispatchQueue.main.async {
                self.redEyedImages[capturedURL] = result
                self.clearCachesDownstream(of: .redEyeRemoval, for: capturedURL)
                self.editStacks[capturedURL, default: EditStack()].append(.redEyeRemoval)
                self.effectImages[capturedURL] = nil
                self.saveFavourites()
                self.updateDisplayImage()
            }
        }
    }

    func restoreBackground() {
        removeEdit(.backgroundRemoval)
    }

    func removeBackgroundOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = currentComposite(for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: srcCG, options: [:])
            let req = VNGenerateForegroundInstanceMaskRequest()
            guard (try? handler.perform([req])) != nil,
                  let result = req.results?.first else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            guard let maskedBuffer = try? result.generateMaskedImage(
                      ofInstances: result.allInstances,
                      from: handler,
                      croppedToInstancesExtent: false) else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            let ciImg = CIImage(cvPixelBuffer: maskedBuffer)
            let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            guard let maskedCG = ctx.createCGImage(ciImg, from: ciImg.extent) else { return }
            let masked = NSImage(cgImage: maskedCG, size: source.size)
            let capturedURL = url
            DispatchQueue.main.async {
                self.backgroundRemovedImages[capturedURL] = masked
                self.clearCachesDownstream(of: .backgroundRemoval, for: capturedURL)
                self.editStacks[capturedURL, default: EditStack()].append(.backgroundRemoval)
                self.effectImages[capturedURL] = nil
                self.saveFavourites()
                self.updateDisplayImage()
            }
        }
    }

    func restoreArtifacts() {
        removeEdit(.artifactRemoval)
    }

    func cancelArtifactRemoval() {
        swinirCancellationToken?.cancel()
        swinirCancellationToken = nil
        isRemovingArtifacts = false
        artifactRemovalProgress = 0
    }

    @discardableResult
    func cancelSwinIRIfRunning() -> Bool {
        if isRemovingArtifacts {
            cancelArtifactRemoval()
            return true
        }
        if isAIDenoising && !showAIDenoiseHUD {
            swinirCancellationToken?.cancel()
            swinirCancellationToken = nil
            isAIDenoising = false
            return true
        }
        return false
    }

    // swiftlint:disable:next function_body_length
    func removeArtifactsOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = currentComposite(for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isRemovingArtifacts = true
        artifactRemovalProgress = 0
        let token = SwinIRCancellationToken()
        swinirCancellationToken = token

        runSwinIRInference(srcCG: srcCG, source: source, label: "Artifact Removal", token: token, progressHandler: { self.artifactRemovalProgress = $0 }) { result in
            guard let result else {
                self.isRemovingArtifacts = false
                return
            }
            self.artifactRemovedImages[url] = result
            self.clearCachesDownstream(of: .artifactRemoval, for: url)
            self.editStacks[url, default: EditStack()].append(.artifactRemoval)
            self.effectImages[url] = nil
            self.isRemovingArtifacts = false
            self.saveFavourites()
            self.updateDisplayImage()
        }
    }

    func removeColorization() {
        removeEdit(.colorize)
    }

    private func imageAppearsGrayscale(_ cgImage: CGImage) -> Bool {
        if cgImage.colorSpace?.model == .monochrome { return true }
        let sampleSize = 64
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: nil, width: sampleSize, height: sampleSize,
                                   bitsPerComponent: 8, bytesPerRow: sampleSize * 4,
                                   space: cs, bitmapInfo: bi) else { return false }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        guard let data = ctx.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: sampleSize * sampleSize * 4)
        var chromaSum: Int = 0
        let total = sampleSize * sampleSize
        for i in 0..<total {
            let b = Int(pixels[i * 4 + 0])
            let g = Int(pixels[i * 4 + 1])
            let r = Int(pixels[i * 4 + 2])
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            chromaSum += (maxC - minC)
        }
        let avgChroma = Double(chromaSum) / Double(total)
        return avgChroma < 5.0
    }

    // swiftlint:disable:next function_body_length
    func colorizeCurrentImage(force: Bool = false) {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = currentComposite(for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        if !force && !imageAppearsGrayscale(srcCG) {
            showColorConfirmAlert = true
            return
        }

        isColorizing = true

        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelURL = Bundle.main.url(forResource: "DDColor_paper_tiny", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "DDColor_paper_tiny", withExtension: "mlpackage") else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }

            let imgW = srcCG.width
            let imgH = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

            guard let readCtx = CGContext(data: nil, width: imgW, height: imgH,
                                           bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                           space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }
            readCtx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let pixelData = readCtx.data else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }
            let pixels = pixelData.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

            var srcL = [Float](repeating: 0, count: imgW * imgH)
            var srcA = [Float](repeating: 0, count: imgW * imgH)
            var srcB = [Float](repeating: 0, count: imgW * imgH)

            for i in 0..<(imgW * imgH) {
                let bVal = Float(pixels[i * 4 + 0]) / 255.0
                let gVal = Float(pixels[i * 4 + 1]) / 255.0
                let rVal = Float(pixels[i * 4 + 2]) / 255.0

                let rLin = rVal <= 0.04045 ? rVal / 12.92 : pow((rVal + 0.055) / 1.055, 2.4)
                let gLin = gVal <= 0.04045 ? gVal / 12.92 : pow((gVal + 0.055) / 1.055, 2.4)
                let bLin = bVal <= 0.04045 ? bVal / 12.92 : pow((bVal + 0.055) / 1.055, 2.4)

                var x = (rLin * 0.4124564 + gLin * 0.3575761 + bLin * 0.1804375) / 0.95047
                var y = rLin * 0.2126729 + gLin * 0.7151522 + bLin * 0.0721750
                var z = (rLin * 0.0193339 + gLin * 0.1191920 + bLin * 0.9503041) / 1.08883

                x = x > 0.008856 ? pow(x, 1.0 / 3.0) : (7.787 * x + 16.0 / 116.0)
                y = y > 0.008856 ? pow(y, 1.0 / 3.0) : (7.787 * y + 16.0 / 116.0)
                z = z > 0.008856 ? pow(z, 1.0 / 3.0) : (7.787 * z + 16.0 / 116.0)

                srcL[i] = 116.0 * y - 16.0
                srcA[i] = 500.0 * (x - y)
                srcB[i] = 200.0 * (y - z)
            }

            let modelSize = 512
            guard let inArr = try? MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32) else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }

            inArr.withUnsafeMutableBytes { buf, _ in
                let ptr = buf.bindMemory(to: Float.self)
                let planeSize = modelSize * modelSize
                for row in 0..<modelSize {
                    for col in 0..<modelSize {
                        let srcRow = row * imgH / modelSize
                        let srcCol = col * imgW / modelSize
                        let lNorm = srcL[srcRow * imgW + srcCol] / 100.0
                        let pos = row * modelSize + col
                        ptr[0 * planeSize + pos] = lNorm
                        ptr[1 * planeSize + pos] = lNorm
                        ptr[2 * planeSize + pos] = lNorm
                    }
                }
            }

            guard let inFeatures = try? MLDictionaryFeatureProvider(
                      dictionary: ["gray_rgb": MLFeatureValue(multiArray: inArr)]),
                  let outFeatures = try? model.prediction(from: inFeatures),
                  let abArr = outFeatures.featureValue(for: "ab_channels")?.multiArrayValue else {
                DispatchQueue.main.async { self.isColorizing = false }
                return
            }

            let isFP16 = abArr.dataType == .float16
            let abPtr16 = isFP16 ? abArr.dataPointer.bindMemory(to: UInt16.self, capacity: abArr.count) : nil
            let abPtr32 = isFP16 ? nil : abArr.dataPointer.bindMemory(to: Float.self, capacity: abArr.count)
            let abPlane = modelSize * modelSize

            var outPixels = [UInt8](repeating: 255, count: imgW * imgH * 4)
            for row in 0..<imgH {
                let mRow = row * modelSize / imgH
                for col in 0..<imgW {
                    let mCol = col * modelSize / imgW
                    let mPos = mRow * modelSize + mCol
                    let predA: Float
                    let predB: Float
                    if isFP16, let ptr = abPtr16 {
                        predA = Float(Float16(bitPattern: ptr[0 * abPlane + mPos]))
                        predB = Float(Float16(bitPattern: ptr[1 * abPlane + mPos]))
                    } else if let ptr = abPtr32 {
                        predA = ptr[0 * abPlane + mPos]
                        predB = ptr[1 * abPlane + mPos]
                    } else {
                        predA = 0; predB = 0
                    }

                    let srcIdx = row * imgW + col
                    let labL = srcL[srcIdx]
                    let labA = predA
                    let labB = predB

                    let fy = (labL + 16.0) / 116.0
                    let fx = labA / 500.0 + fy
                    let fz = fy - labB / 200.0

                    let xr = fx * fx * fx > 0.008856 ? fx * fx * fx : (fx - 16.0 / 116.0) / 7.787
                    let yr = fy * fy * fy > 0.008856 ? fy * fy * fy : (fy - 16.0 / 116.0) / 7.787
                    let zr = fz * fz * fz > 0.008856 ? fz * fz * fz : (fz - 16.0 / 116.0) / 7.787

                    let xw = xr * 0.95047
                    let yw = yr
                    let zw = zr * 1.08883

                    var rLin = xw *  3.2404542 + yw * -1.5371385 + zw * -0.4985314
                    var gLin = xw * -0.9692660 + yw *  1.8760108 + zw *  0.0415560
                    var bLin = xw *  0.0556434 + yw * -0.2040259 + zw *  1.0572252

                    rLin = max(0, min(1, rLin))
                    gLin = max(0, min(1, gLin))
                    bLin = max(0, min(1, bLin))

                    let rS = rLin <= 0.0031308 ? 12.92 * rLin : 1.055 * pow(rLin, 1.0 / 2.4) - 0.055
                    let gS = gLin <= 0.0031308 ? 12.92 * gLin : 1.055 * pow(gLin, 1.0 / 2.4) - 0.055
                    let bS = bLin <= 0.0031308 ? 12.92 * bLin : 1.055 * pow(bLin, 1.0 / 2.4) - 0.055

                    let pIdx = srcIdx * 4
                    outPixels[pIdx + 0] = UInt8(min(255, max(0, Int(bS * 255))))
                    outPixels[pIdx + 1] = UInt8(min(255, max(0, Int(gS * 255))))
                    outPixels[pIdx + 2] = UInt8(min(255, max(0, Int(rS * 255))))
                    outPixels[pIdx + 3] = 255
                }
            }

            let capturedURL = url
            outPixels.withUnsafeMutableBytes { ptr in
                guard let outCtx = CGContext(data: ptr.baseAddress, width: imgW, height: imgH,
                                              bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                              space: cs, bitmapInfo: bi),
                      let outCG = outCtx.makeImage() else {
                    DispatchQueue.main.async { self.isColorizing = false }
                    return
                }
                let result = NSImage(cgImage: outCG, size: source.size)
                DispatchQueue.main.async {
                    self.colorizedImages[capturedURL] = result
                    self.clearCachesDownstream(of: .colorize, for: capturedURL)
                    self.editStacks[capturedURL, default: EditStack()].append(.colorize)
                    self.effectImages[capturedURL] = nil
                    self.isColorizing = false
                    self.saveFavourites()
                    self.updateDisplayImage()
                }
            }
        }
    }

    // swiftlint:disable:next function_body_length
    func restoreFacesOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring, !isColorizing else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = currentComposite(for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isFaceRestoring = true
        faceRestoreProgress = 0.0

        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: srcCG, options: [:]).perform([req])
            guard let faces = req.results as? [VNFaceObservation], !faces.isEmpty else {
                DispatchQueue.main.async { self.isFaceRestoring = false; self.showNoFaceAlert = true }
                return
            }

            guard let modelURL = Bundle.main.url(forResource: "CodeFormer", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "CodeFormer", withExtension: "mlpackage") else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }

            let imgWidth = srcCG.width, imgHeight = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(data: nil, width: imgWidth, height: imgHeight,
                                      bitsPerComponent: 8, bytesPerRow: imgWidth * 4,
                                      space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

            for (idx, face) in faces.enumerated() {
                let bb = face.boundingBox
                let faceW = max(1, Int(bb.size.width * CGFloat(imgWidth)))
                let faceH = max(1, Int(bb.size.height * CGFloat(imgHeight)))
                let side = max(faceW, faceH)
                let padded = Int(Double(side) * 1.3)
                let cx = Int(bb.origin.x * CGFloat(imgWidth)) + faceW / 2
                let cy = Int((1 - bb.origin.y - bb.size.height) * CGFloat(imgHeight)) + faceH / 2
                let cropX = max(0, cx - padded / 2)
                let cropY = max(0, cy - padded / 2)
                let cropW = min(imgWidth - cropX, padded)
                let cropH = min(imgHeight - cropY, padded)
                guard cropW > 0, cropH > 0,
                      let cropCG = srcCG.cropping(to: CGRect(x: cropX, y: cropY,
                                                              width: cropW, height: cropH)) else { continue }

                var raw = [UInt8](repeating: 0, count: 512 * 512 * 4)
                raw.withUnsafeMutableBytes { ptr in
                    if let faceCtx = CGContext(data: ptr.baseAddress, width: 512, height: 512,
                                              bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                              space: cs, bitmapInfo: bi) {
                        faceCtx.draw(cropCG, in: CGRect(x: 0, y: 0, width: 512, height: 512))
                    }
                }

                guard let arr = try? MLMultiArray(shape: [1, 3, 512, 512], dataType: .float16) else { continue }
                arr.withUnsafeMutableBytes { buf, _ in
                    let ptr = buf.bindMemory(to: Float16.self)
                    for i in 0..<(512 * 512) {
                        ptr[0 * 512 * 512 + i] = Float16(Float(raw[i * 4])     / 127.5 - 1)
                        ptr[1 * 512 * 512 + i] = Float16(Float(raw[i * 4 + 1]) / 127.5 - 1)
                        ptr[2 * 512 * 512 + i] = Float16(Float(raw[i * 4 + 2]) / 127.5 - 1)
                    }
                }

                guard let featureInput = try? MLDictionaryFeatureProvider(
                          dictionary: ["face": MLFeatureValue(multiArray: arr)]),
                      let out = try? model.prediction(from: featureInput),
                      let outArr = out.featureValue(for: "restored_face")?.multiArrayValue else { continue }

                var outRaw = [UInt8](repeating: 255, count: 512 * 512 * 4)
                outArr.withUnsafeBytes { buf in
                    let ptr = buf.bindMemory(to: Float16.self)
                    for i in 0..<(512 * 512) {
                        outRaw[i*4]   = UInt8(min(255, max(0, Int((Float(ptr[0*512*512+i])+1)*127.5))))
                        outRaw[i*4+1] = UInt8(min(255, max(0, Int((Float(ptr[1*512*512+i])+1)*127.5))))
                        outRaw[i*4+2] = UInt8(min(255, max(0, Int((Float(ptr[2*512*512+i])+1)*127.5))))
                    }
                }

                let pasteY = imgHeight - cropY - cropH
                outRaw.withUnsafeMutableBytes { ptr in
                    if let restoredCtx = CGContext(data: ptr.baseAddress, width: 512, height: 512,
                                                   bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                                   space: cs, bitmapInfo: bi),
                       let restoredCG = restoredCtx.makeImage() {
                        ctx.draw(restoredCG, in: CGRect(x: cropX, y: pasteY, width: cropW, height: cropH))
                    }
                }

                let progress = Double(idx + 1) / Double(faces.count)
                DispatchQueue.main.async { self.faceRestoreProgress = progress }
            }

            guard let finalCG = ctx.makeImage() else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            let result = NSImage(cgImage: finalCG, size: NSSize(width: imgWidth, height: imgHeight))
            let capturedURL = url
            DispatchQueue.main.async {
                self.faceRestoredImages[capturedURL] = result
                self.clearCachesDownstream(of: .faceRestore, for: capturedURL)
                self.editStacks[capturedURL, default: EditStack()].append(.faceRestore)
                self.effectImages[capturedURL] = nil
                self.isFaceRestoring = false
                self.saveFavourites()
                self.updateDisplayImage()
            }
        }
    }

    @ViewBuilder var aiDenoiseHUD: some View {
        if showAIDenoiseHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("AI Denoise")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        if isAIDenoising {
                            Text("\(Int(aiDenoiseProgress * 100))%")
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text("\(Int(aiDenoiseStrength))%")
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    if isAIDenoising {
                        ProgressView(value: aiDenoiseProgress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                    } else {
                        Slider(value: $aiDenoiseStrength, in: 0...100, step: 1)
                            .onChange(of: aiDenoiseStrength) { _, _ in
                                DispatchQueue.main.async { updateAIDenoiseBlend() }
                            }
                            .tint(.white)
                    }
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelAIDenoiseHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyAIDenoise() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAIDenoising)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .frame(maxWidth: 360)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    var progressOverlays: some View {
        if isProcessing {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("AI Upscaling Image (\(activeUpscaleScale)x)\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)

                    ProgressView(value: upscaleProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                        .accessibilityLabel("Upscale progress")
                        .accessibilityValue("\(Int(upscaleProgress * 100)) percent")

                    Text("\(Int(upscaleProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .accessibilityHidden(true)

                    Button("Cancel", action: cancelUpscale)
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityLabel("Cancel upscaling")
                        .accessibilityHint("Stops the AI upscaling process")
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        if isFaceRestoring {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("Restoring Faces\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView(value: faceRestoreProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                    Text("\(Int(faceRestoreProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        if isRemovingArtifacts {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("Removing Artifacts\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView(value: artifactRemovalProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                    Text("\(Int(artifactRemovalProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                    Button("Cancel") { cancelArtifactRemoval() }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 4)
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        if isColorizing {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("Colorizing\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                        .tint(.white)
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    var debugOverlay: some View {
        if showDebugWindow {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Upscaling Debug Output")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Close") {
                            showDebugWindow = false
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Close debug window")
                    }

                    ScrollView {
                        Text(debugOutput)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 300)

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.white)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.9))
                .cornerRadius(12)
                .frame(width: 700)
                .padding(.bottom, 40)
            }
        }
    }

    func removeAIDenoise() {
        removeEdit(.aiDenoise)
    }

    func openAIDenoiseHUD() {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing, !isAIDenoising else { return }
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !showAIDenoiseHUD else { return }

        aiDenoiseBaseImage = compositeBeforeStep(.aiDenoise, for: url)
        aiDenoiseStrength = 100.0
        showAIDenoiseHUD = true

        if let cached = aiDenoiseRawImages[url] {
            aiDenoiseMLImage = cached
            updateAIDenoiseBlend()
        } else {
            runAIDenoiseInference()
        }
    }

    func applyAIDenoiseDirectly(strength: Double) {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing, !isAIDenoising else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = compositeBeforeStep(.aiDenoise, for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isAIDenoising = true
        aiDenoiseProgress = 0
        let token = SwinIRCancellationToken()
        swinirCancellationToken = token
        runSwinIRInference(srcCG: srcCG, source: source, label: "AI Denoise", token: token, progressHandler: { self.aiDenoiseProgress = $0 }) { mlImage in
            guard let mlImage else {
                self.isAIDenoising = false
                return
            }
            let blended = self.blendImages(base: source, overlay: mlImage, strength: strength / 100.0)
            self.aiDenoiseRawImages[url] = mlImage
            self.aiDenoisedImages[url] = blended
            self.clearCachesDownstream(of: .aiDenoise, for: url)
            self.editStacks[url, default: EditStack()].append(.aiDenoise(strength: strength))
            self.effectImages[url] = nil
            self.isAIDenoising = false
            self.saveFavourites()
            self.updateDisplayImage()
        }
    }

    private func runAIDenoiseInference() {
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = aiDenoiseBaseImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isAIDenoising = true
        aiDenoiseProgress = 0
        let token = SwinIRCancellationToken()
        swinirCancellationToken = token

        runSwinIRInference(srcCG: srcCG, source: source, label: "AI Denoise", token: token, progressHandler: { self.aiDenoiseProgress = $0 }) { mlImage in
            self.isAIDenoising = false
            guard let mlImage else {
                self.cancelAIDenoiseHUD()
                return
            }
            guard self.imageLoader.currentImageURL == url, self.showAIDenoiseHUD else { return }
            self.aiDenoiseMLImage = mlImage
            self.aiDenoiseRawImages[url] = mlImage
            self.updateAIDenoiseBlend()
        }
    }

    func updateAIDenoiseBlend() {
        guard let base = aiDenoiseBaseImage, let ml = aiDenoiseMLImage else { return }
        let strength = aiDenoiseStrength / 100.0
        if strength <= 0 {
            currentDisplayImage = base
            return
        }
        if strength >= 1.0 {
            currentDisplayImage = ml
            return
        }
        currentDisplayImage = blendImages(base: base, overlay: ml, strength: strength)
    }

    func applyAIDenoise() {
        guard !isAIDenoising else { return }
        guard let url = imageLoader.currentImageURL,
              let result = currentDisplayImage else { cancelAIDenoiseHUD(); return }
        aiDenoisedImages[url] = result
        clearCachesDownstream(of: .aiDenoise, for: url)
        editStacks[url, default: EditStack()].append(.aiDenoise(strength: aiDenoiseStrength))
        effectImages[url] = nil
        saveFavourites()
        showAIDenoiseHUD = false
        aiDenoiseBaseImage = nil
        aiDenoiseMLImage = nil
        updateDisplayImage()
    }

    func cancelAIDenoiseHUD() {
        guard showAIDenoiseHUD else { return }
        swinirCancellationToken?.cancel()
        swinirCancellationToken = nil
        showAIDenoiseHUD = false
        isAIDenoising = false
        aiDenoiseBaseImage = nil
        aiDenoiseMLImage = nil
        updateDisplayImage()
    }

    private func blendImages(base: NSImage, overlay: NSImage, strength: Double) -> NSImage {
        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let overlayCG = overlay.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return base }
        let w = baseCG.width, h = baseCG.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let baseCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: w * 4, space: cs, bitmapInfo: bi),
              let ovCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: cs, bitmapInfo: bi) else { return base }
        baseCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        ovCtx.draw(overlayCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let bData = baseCtx.data, let oData = ovCtx.data else { return base }
        let bPtr = bData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let oPtr = oData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let s = Float(strength)
        let inv = 1.0 - s

        var out = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let idx = i * 4
            let v0 = Float(bPtr[idx + 0]) * inv + Float(oPtr[idx + 0]) * s; out[idx + 0] = UInt8(v0.isFinite ? min(255, max(0, Int(v0))) : 0)
            let v1 = Float(bPtr[idx + 1]) * inv + Float(oPtr[idx + 1]) * s; out[idx + 1] = UInt8(v1.isFinite ? min(255, max(0, Int(v1))) : 0)
            let v2 = Float(bPtr[idx + 2]) * inv + Float(oPtr[idx + 2]) * s; out[idx + 2] = UInt8(v2.isFinite ? min(255, max(0, Int(v2))) : 0)
            out[idx + 3] = 255
        }

        return out.withUnsafeMutableBytes { ptr -> NSImage in
            guard let outCtx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: cs, bitmapInfo: bi),
                  let outCG = outCtx.makeImage() else { return base }
            return NSImage(cgImage: outCG, size: base.size)
        }
    }

    // swiftlint:disable:next function_body_length
    private func runSwinIRInference(srcCG: CGImage, source: NSImage, label: String, token: SwinIRCancellationToken, progressHandler: (@MainActor (Double) -> Void)? = nil, completion: @escaping @MainActor (NSImage?) -> Void) {
        DispatchQueue.main.async {
            self.debugOutput = "Starting \(label)...\n"
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = CFAbsoluteTimeGetCurrent()

            guard let modelURL = Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlpackage") else {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: SwinIR_color_jpeg40 model not found in bundle\n"
                    completion(nil)
                }
                return
            }
            DispatchQueue.main.async {
                self.debugOutput += "Loading model...\n"
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU

            var loadedModel: MLModel?
            let loadSemaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                loadedModel = try? MLModel(contentsOf: modelURL, configuration: cfg)
                loadSemaphore.signal()
            }
            let loadResult = loadSemaphore.wait(timeout: .now() + 30)

            if token.isCancelled {
                DispatchQueue.main.async {
                    self.debugOutput += "CANCELLED: \(label) stopped during model load\n"
                    completion(nil)
                }
                return
            }

            if loadResult == .timedOut {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: Model load timed out after 30s (possible ANE compile stall)\n"
                    completion(nil)
                }
                return
            }

            guard let model = loadedModel else {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: Failed to load SwinIR model\n"
                    completion(nil)
                }
                return
            }

            let imgW = srcCG.width
            let imgH = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

            guard let readCtx = CGContext(data: nil, width: imgW, height: imgH,
                                           bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                           space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: Failed to create drawing context\n"
                    completion(nil)
                }
                return
            }
            readCtx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let pixelData = readCtx.data else {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: Failed to read pixel data\n"
                    completion(nil)
                }
                return
            }
            let pixels = pixelData.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

            let tileSize = 126
            let tileOverlap = 16

            func tileStarts(_ total: Int) -> [Int] {
                guard total > tileSize else { return [0] }
                var positions: [Int] = []
                let stride = tileSize - tileOverlap
                var pos = 0
                while pos < total {
                    if pos + tileSize >= total {
                        positions.append(max(0, total - tileSize))
                        break
                    }
                    positions.append(pos)
                    pos += stride
                }
                return positions
            }

            let xStarts = tileStarts(imgW)
            let yStarts = tileStarts(imgH)
            let totalTiles = xStarts.count * yStarts.count

            DispatchQueue.main.async {
                self.debugOutput += "Image: \(imgW)×\(imgH), \(totalTiles) tile\(totalTiles == 1 ? "" : "s")\n"
                self.debugOutput += "Running \(label) via Core ML...\n"
            }

            var accR = [Float](repeating: 0, count: imgW * imgH)
            var accG = [Float](repeating: 0, count: imgW * imgH)
            var accB = [Float](repeating: 0, count: imgW * imgH)
            var accW = [Float](repeating: 0, count: imgW * imgH)

            var tilesDone = 0

            for y0 in yStarts {
                for x0 in xStarts {
                    if token.isCancelled {
                        let done = tilesDone
                        DispatchQueue.main.async {
                            self.debugOutput += "CANCELLED: \(label) stopped after \(done)/\(totalTiles) tiles\n"
                            completion(nil)
                        }
                        return
                    }
                    let y1 = min(y0 + tileSize, imgH)
                    let x1 = min(x0 + tileSize, imgW)
                    let tileH = y1 - y0
                    let tileW = x1 - x0

                    guard let inArr = try? MLMultiArray(shape: [1, 3, 126, 126], dataType: .float32) else { continue }
                    let inChStride = inArr.strides[1].intValue
                    let inRowStride = inArr.strides[2].intValue
                    inArr.withUnsafeMutableBytes { buf, _ in
                        let ptr = buf.bindMemory(to: Float.self)
                        for row in 0..<tileSize {
                            for col in 0..<tileSize {
                                let srcRow = min(y0 + min(row, tileH - 1), imgH - 1)
                                let srcCol = min(x0 + min(col, tileW - 1), imgW - 1)
                                let pixIdx = (srcRow * imgW + srcCol) * 4
                                let pos = row * inRowStride + col
                                ptr[0 * inChStride + pos] = Float(pixels[pixIdx + 2]) / 255.0
                                ptr[1 * inChStride + pos] = Float(pixels[pixIdx + 1]) / 255.0
                                ptr[2 * inChStride + pos] = Float(pixels[pixIdx + 0]) / 255.0
                            }
                        }
                    }

                    guard let inFeatures = try? MLDictionaryFeatureProvider(
                              dictionary: ["image": MLFeatureValue(multiArray: inArr)]),
                          let outFeatures = try? model.prediction(from: inFeatures),
                          let outArr = outFeatures.featureValue(for: "restored_image")?.multiArrayValue else { continue }

                    let rampPx = tileOverlap
                    let isFP16 = outArr.dataType == .float16
                    let rawPtr16 = isFP16 ? outArr.dataPointer.bindMemory(to: UInt16.self, capacity: outArr.count) : nil
                    let rawPtr32 = isFP16 ? nil : outArr.dataPointer.bindMemory(to: Float.self, capacity: outArr.count)
                    let outChStride = outArr.strides[1].intValue
                    let outRowStride = outArr.strides[2].intValue

                    if tilesDone == 0 {
                        let strides = outArr.strides.map { $0.intValue }
                        DispatchQueue.main.async {
                            self.debugOutput += "Output MLMultiArray strides: \(strides)\n"
                        }
                    }

                    for ty in 0..<tileH {
                        let gy = y0 + ty
                        for tx in 0..<tileW {
                            let gx = x0 + tx
                            var w: Float = 1.0
                            if rampPx > 0 {
                                if y0 > 0 && ty < rampPx { w *= Float(ty) / Float(rampPx) }
                                if y1 < imgH && ty >= tileH - rampPx { w *= Float(tileH - 1 - ty) / Float(rampPx) }
                                if x0 > 0 && tx < rampPx { w *= Float(tx) / Float(rampPx) }
                                if x1 < imgW && tx >= tileW - rampPx { w *= Float(tileW - 1 - tx) / Float(rampPx) }
                            }
                            let idx = gy * imgW + gx
                            let pos = ty * outRowStride + tx
                            let r0: Float, g0: Float, b0: Float
                            if isFP16, let ptr = rawPtr16 {
                                r0 = Float(Float16(bitPattern: ptr[0 * outChStride + pos]))
                                g0 = Float(Float16(bitPattern: ptr[1 * outChStride + pos]))
                                b0 = Float(Float16(bitPattern: ptr[2 * outChStride + pos]))
                            } else if let ptr = rawPtr32 {
                                r0 = ptr[0 * outChStride + pos]
                                g0 = ptr[1 * outChStride + pos]
                                b0 = ptr[2 * outChStride + pos]
                            } else {
                                (r0, g0, b0) = (0, 0, 0)
                            }
                            accR[idx] += r0 * w
                            accG[idx] += g0 * w
                            accB[idx] += b0 * w
                            accW[idx] += w
                        }
                    }

                    tilesDone += 1
                    let progress = Double(tilesDone) / Double(totalTiles)
                    if let progressHandler {
                        DispatchQueue.main.async { progressHandler(progress) }
                    }
                }
            }

            if token.isCancelled {
                DispatchQueue.main.async {
                    self.debugOutput += "CANCELLED: \(label) result discarded after tile loop\n"
                    completion(nil)
                }
                return
            }

            var outPixels = [UInt8](repeating: 255, count: imgW * imgH * 4)
            for i in 0..<(imgW * imgH) {
                let dw = accW[i] > 0 ? accW[i] : 1
                let vB = accB[i] / dw * 255; outPixels[i * 4 + 0] = UInt8(vB.isFinite ? min(255, max(0, Int(vB))) : 0)
                let vG = accG[i] / dw * 255; outPixels[i * 4 + 1] = UInt8(vG.isFinite ? min(255, max(0, Int(vG))) : 0)
                let vR = accR[i] / dw * 255; outPixels[i * 4 + 2] = UInt8(vR.isFinite ? min(255, max(0, Int(vR))) : 0)
                outPixels[i * 4 + 3] = 255
            }

            outPixels.withUnsafeMutableBytes { ptr in
                guard let outCtx = CGContext(data: ptr.baseAddress, width: imgW, height: imgH,
                                              bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                              space: cs, bitmapInfo: bi),
                      let outCG = outCtx.makeImage() else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Failed to create output image\n"
                        completion(nil)
                    }
                    return
                }
                if token.isCancelled {
                    DispatchQueue.main.async {
                        self.debugOutput += "CANCELLED: \(label) result discarded\n"
                        completion(nil)
                    }
                    return
                }
                let result = NSImage(cgImage: outCG, size: source.size)
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                DispatchQueue.main.async {
                    self.debugOutput += String(format: "SUCCESS: %dx%d in %.1fs\n", imgW, imgH, elapsed)
                    completion(result)
                }
            }
        }
    }

    @ViewBuilder
    var beforeAfterLabel: some View {
        if showingOriginal {
            VStack {
                Text("Original")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.7))
                    .cornerRadius(6)
                    .padding(.top, 20)
                Spacer()
            }
        }
    }
}
