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
