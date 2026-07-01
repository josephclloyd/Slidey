import AppKit
import CoreImage
import CoreML
import Vision

extension SlideshowView {

    func removeFaceRestoration() {
        guard let url = imageLoader.currentImageURL else { return }
        faceRestoredImages[url] = nil
        updateDisplayImage()
    }

    func removeRedEyeCorrection() {
        guard let url = imageLoader.currentImageURL else { return }
        redEyedImages[url] = nil
        updateDisplayImage()
    }

    func applyRedEyeOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
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
                self.setDisplay(base: result, for: capturedURL)
            }
        }
    }

    func restoreBackground() {
        guard let url = imageLoader.currentImageURL else { return }
        backgroundRemovedImages[url] = nil
        updateDisplayImage()
    }

    func removeBackgroundOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
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
                self.setDisplay(base: masked, for: capturedURL)
            }
        }
    }

    func restoreArtifacts() {
        guard let url = imageLoader.currentImageURL else { return }
        artifactRemovedImages[url] = nil
        updateDisplayImage()
    }

    // swiftlint:disable:next function_body_length
    func removeArtifactsOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isRemovingArtifacts = true
        artifactRemovalProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelURL = Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlpackage") else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }

            let imgW = srcCG.width
            let imgH = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

            guard let readCtx = CGContext(data: nil, width: imgW, height: imgH,
                                          bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                          space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }
            readCtx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let pixelData = readCtx.data else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
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

            var accR = [Float](repeating: 0, count: imgW * imgH)
            var accG = [Float](repeating: 0, count: imgW * imgH)
            var accB = [Float](repeating: 0, count: imgW * imgH)
            var accW = [Float](repeating: 0, count: imgW * imgH)

            var tilesDone = 0

            for y0 in yStarts {
                for x0 in xStarts {
                    let y1 = min(y0 + tileSize, imgH)
                    let x1 = min(x0 + tileSize, imgW)
                    let tileH = y1 - y0
                    let tileW = x1 - x0

                    guard let inArr = try? MLMultiArray(shape: [1, 3, 126, 126], dataType: .float32) else { continue }
                    inArr.withUnsafeMutableBytes { buf, _ in
                        let ptr = buf.bindMemory(to: Float.self)
                        for row in 0..<tileSize {
                            for col in 0..<tileSize {
                                let srcRow = min(y0 + min(row, tileH - 1), imgH - 1)
                                let srcCol = min(x0 + min(col, tileW - 1), imgW - 1)
                                let pixIdx = (srcRow * imgW + srcCol) * 4
                                let pos = row * tileSize + col
                                ptr[0 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 2]) / 255.0
                                ptr[1 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 1]) / 255.0
                                ptr[2 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 0]) / 255.0
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
                            let pos = ty * tileSize + tx
                            let r0: Float, g0: Float, b0: Float
                            if isFP16, let ptr = rawPtr16 {
                                r0 = Float(Float16(bitPattern: ptr[0 * tileSize * tileSize + pos]))
                                g0 = Float(Float16(bitPattern: ptr[1 * tileSize * tileSize + pos]))
                                b0 = Float(Float16(bitPattern: ptr[2 * tileSize * tileSize + pos]))
                            } else if let ptr = rawPtr32 {
                                r0 = ptr[0 * tileSize * tileSize + pos]
                                g0 = ptr[1 * tileSize * tileSize + pos]
                                b0 = ptr[2 * tileSize * tileSize + pos]
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
                    DispatchQueue.main.async { self.artifactRemovalProgress = progress }
                }
            }

            var outPixels = [UInt8](repeating: 255, count: imgW * imgH * 4)
            for i in 0..<(imgW * imgH) {
                let dw = accW[i] > 0 ? accW[i] : 1
                outPixels[i * 4 + 0] = UInt8(min(255, max(0, Int(accB[i] / dw * 255))))
                outPixels[i * 4 + 1] = UInt8(min(255, max(0, Int(accG[i] / dw * 255))))
                outPixels[i * 4 + 2] = UInt8(min(255, max(0, Int(accR[i] / dw * 255))))
                outPixels[i * 4 + 3] = 255
            }

            let capturedURL = url
            outPixels.withUnsafeMutableBytes { ptr in
                guard let outCtx = CGContext(data: ptr.baseAddress, width: imgW, height: imgH,
                                             bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                             space: cs, bitmapInfo: bi),
                      let outCG = outCtx.makeImage() else {
                    DispatchQueue.main.async { self.isRemovingArtifacts = false }
                    return
                }
                let result = NSImage(cgImage: outCG, size: source.size)
                DispatchQueue.main.async {
                    self.artifactRemovedImages[capturedURL] = result
                    self.setDisplay(base: result, for: capturedURL)
                    self.isRemovingArtifacts = false
                }
            }
        }
    }

    func removeColorization() {
        guard let url = imageLoader.currentImageURL else { return }
        colorizedImages[url] = nil
        updateDisplayImage()
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
        guard let source = imageLoader.currentImage else { return }
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
                    self.setDisplay(base: result, for: capturedURL)
                    self.isColorizing = false
                }
            }
        }
    }

    // swiftlint:disable:next function_body_length
    func restoreFacesOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
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
                self.isFaceRestoring = false
                self.setDisplay(base: result, for: capturedURL)
            }
        }
    }
}
