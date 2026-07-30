import SwiftUI
import AppKit
import CoreML

extension SlideshowView {

    func upscaleCurrentImage(scale: Int) {
        guard !isProcessing else { return }
        guard let targetURL = editTargetURL else { return }
        guard let sourceImage = currentComposite(for: targetURL) else { return }

        isProcessing = true
        upscaleCancelled = false
        upscaleProgress = 0
        activeUpscaleScale = scale
        debugOutput = "Starting \(scale)x Core ML upscale...\n"

        let modelName = scale == 2 ? "RealESRGAN_x2plus_522_fp16" : "RealESRGAN_x4plus_522_fp16"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Xcode compiles .mlpackage → .mlmodelc at build time; fall back to
                // .mlpackage for any non-Xcode distribution path.
                guard let pkgURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                                    Bundle.main.url(forResource: modelName, withExtension: "mlpackage",
                                                    subdirectory: "Resources") ??
                                    Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: \(modelName) not found in bundle\n"
                        self.isProcessing = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.debugOutput += "Loading model (may take ~30s on first run)...\n"
                }

                let config = MLModelConfiguration()
                config.computeUnits = .all
                let model = try MLModel(contentsOf: pkgURL, configuration: config)
                let outputKey = model.modelDescription.outputDescriptionsByName.keys.first!

                guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Could not get CGImage from source image\n"
                        self.isProcessing = false
                    }
                    return
                }

                let imgW = cgImage.width
                let imgH = cgImage.height
                let outW = imgW * scale
                let outH = imgH * scale

                DispatchQueue.main.async {
                    self.debugOutput += "Image: \(imgW)×\(imgH) → \(outW)×\(outH)\n"
                    self.debugOutput += "Upscaling via Core ML...\n"
                }

                // Render source image to a flat RGBA UInt8 pixel buffer
                var inputPixels = [UInt8](repeating: 0, count: imgW * imgH * 4)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let drawCtx = CGContext(
                    data: &inputPixels, width: imgW, height: imgH,
                    bitsPerComponent: 8, bytesPerRow: imgW * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Failed to create drawing context\n"
                        self.isProcessing = false
                    }
                    return
                }
                drawCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

                if self.upscaleCancelled {
                    DispatchQueue.main.async { self.isProcessing = false }
                    return
                }

                // Run tiled Core ML inference
                var outputPixels = [UInt8](repeating: 255, count: outW * outH * 4)
                try Self.runTiledUpscale(
                    model: model, outputKey: outputKey,
                    inputPixels: inputPixels, imgW: imgW, imgH: imgH,
                    outputPixels: &outputPixels, outW: outW, outH: outH,
                    scale: scale,
                    isCancelled: { self.upscaleCancelled },
                    onProgress: { p in DispatchQueue.main.async { self.upscaleProgress = p } }
                )

                if self.upscaleCancelled {
                    DispatchQueue.main.async {
                        self.debugOutput += "Upscaling cancelled.\n"
                        self.isProcessing = false
                    }
                    return
                }

                // Wrap output pixel buffer in NSImage
                guard let outCtx = CGContext(
                    data: &outputPixels, width: outW, height: outH,
                    bitsPerComponent: 8, bytesPerRow: outW * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ), let outCGImage = outCtx.makeImage() else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Failed to create output image\n"
                        self.isProcessing = false
                    }
                    return
                }

                let result = NSImage(cgImage: outCGImage, size: NSSize(width: outW, height: outH))
                DispatchQueue.main.async {
                    self.registerUndoForEdit(url: targetURL, actionName: "Upscale")
                    self.upscaledImages[targetURL] = result
                    self.upscaleFactors[targetURL] = scale
                    self.clearCachesDownstream(of: .upscale, for: targetURL)
                    self.editStacks[targetURL, default: EditStack()].append(.upscale(factor: scale))
                    self.effectImages[targetURL] = nil
                    self.upscaleProgress = 1.0
                    self.debugOutput += "SUCCESS: \(imgW)×\(imgH) → \(outW)×\(outH)\n"
                    self.isProcessing = false
                    self.saveFavourites()
                    self.updateDisplayImage()
                }
            } catch {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: \(error.localizedDescription)\n"
                    self.isProcessing = false
                }
            }
        }
    }

    // Runs Real-ESRGAN inference on tiled regions of the input and accumulates
    // results with linear-ramp blending in overlap zones to avoid seams.
    // Tile parameters match the hanxiao/real-esrgan-coreml reference implementation:
    // 512px tiles, 32px overlap, 10px reflect pre-pad, 522×522 model input.
    // swiftlint:disable:next function_parameter_count
    private static func runTiledUpscale(
        model: MLModel, outputKey: String,
        inputPixels: [UInt8], imgW: Int, imgH: Int,
        outputPixels: inout [UInt8], outW: Int, outH: Int,
        scale: Int,
        isCancelled: () -> Bool,
        onProgress: (Double) -> Void
    ) throws {
        let tileSize = 512
        let tileOverlap = 32
        let prePad = 10
        let modelSize = tileSize + prePad  // 522
        let outModelSide = modelSize * scale

        // Float accumulators for weighted blending
        var accR = [Float](repeating: 0, count: outW * outH)
        var accG = [Float](repeating: 0, count: outW * outH)
        var accB = [Float](repeating: 0, count: outW * outH)
        var accW = [Float](repeating: 0, count: outW * outH)

        func tileStarts(total: Int) -> [Int] {
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

        let yStarts = tileStarts(total: imgH)
        let xStarts = tileStarts(total: imgW)
        let totalTiles = yStarts.count * xStarts.count
        var tilesDone = 0

        // Reuse a single MLMultiArray across tiles to avoid per-tile allocation
        let inputArray = try MLMultiArray(
            shape: [1, 3, NSNumber(value: modelSize), NSNumber(value: modelSize)],
            dataType: .float32
        )
        let inPtr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 3 * modelSize * modelSize)

        for y0 in yStarts {
            if isCancelled() { return }
            for x0 in xStarts {
                if isCancelled() { return }

                let y1 = min(y0 + tileSize, imgH)
                let x1 = min(x0 + tileSize, imgW)
                let tileH = y1 - y0
                let tileW = x1 - x0
                let paddedH = tileH + prePad
                let paddedW = tileW + prePad

                // Fill model input (NCHW, float32 [0,1]) with reflect-padded tile data.
                // Two-layer reflect: square-pad (modelSize → paddedH×paddedW) then
                // pre-pad (paddedH → tileH). Uses periodic reflect-clamp so multiple
                // bounces are handled correctly when the tile is smaller than prePad or
                // when the square-pad zone is large relative to paddedH.
                func ri(_ i: Int, _ n: Int) -> Int {
                    guard n > 1 else { return 0 }
                    let p = 2 * (n - 1)
                    let j = ((i % p) + p) % p
                    return j < n ? j : p - j
                }
                for row in 0..<modelSize {
                    for col in 0..<modelSize {
                        let tr = ri(ri(row, paddedH), tileH)
                        let tc = ri(ri(col, paddedW), tileW)
                        let pixIdx = ((y0 + tr) * imgW + (x0 + tc)) * 4
                        let pos = row * modelSize + col
                        inPtr[0 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx])     / 255.0
                        inPtr[1 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx + 1]) / 255.0
                        inPtr[2 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx + 2]) / 255.0
                    }
                }

                let inFeatures = try MLDictionaryFeatureProvider(
                    dictionary: ["input": MLFeatureValue(multiArray: inputArray)]
                )
                let outFeatures = try model.prediction(from: inFeatures)
                guard let outArray = outFeatures.featureValue(for: outputKey)?.multiArrayValue else {
                    throw NSError(domain: "SlideyUpscale", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Model produced no output"])
                }

                // Read output using raw pointer + actual strides to handle fp16/fp32
                // regardless of how Core ML arranges memory. MLShapedArray<Float> crashes
                // when the underlying array is Float16 (type mismatch is a fatal error).
                let outRank = outArray.shape.count
                let outStrides = outArray.strides
                // For [1,C,H,W] outRank=4 → chanSt=strides[1]; for [C,H,W] → strides[0]
                let chanSt = outStrides[outRank - 3].intValue
                let rowSt  = outStrides[outRank - 2].intValue
                let colSt  = outStrides[outRank - 1].intValue

                // Accumulate tile output with linear-ramp blend weights in overlap zones
                let rampPx = tileOverlap * scale

                // Hoist the data-type branch outside the pixel loop
                let isFP16 = outArray.dataType == .float16
                let rawPtr16 = isFP16 ? outArray.dataPointer.bindMemory(
                    to: UInt16.self, capacity: outArray.count) : nil
                let rawPtr32 = isFP16 ? nil : outArray.dataPointer.bindMemory(
                    to: Float.self, capacity: outArray.count)

                for ty in 0..<tileH * scale {
                    let gy = y0 * scale + ty
                    for tx in 0..<tileW * scale {
                        let gx = x0 * scale + tx
                        var w: Float = 1.0
                        if rampPx > 0 {
                            if y0 > 0 && ty < rampPx            { w *= Float(ty) / Float(rampPx) }
                            if y1 < imgH && ty >= tileH * scale - rampPx { w *= Float(tileH * scale - 1 - ty) / Float(rampPx) }
                            if x0 > 0 && tx < rampPx            { w *= Float(tx) / Float(rampPx) }
                            if x1 < imgW && tx >= tileW * scale - rampPx { w *= Float(tileW * scale - 1 - tx) / Float(rampPx) }
                        }
                        let idx = gy * outW + gx
                        let base = ty * rowSt + tx * colSt
                        let r0: Float, g0: Float, b0: Float
                        if isFP16, let ptr = rawPtr16 {
                            r0 = Float(Float16(bitPattern: ptr[base]))
                            g0 = Float(Float16(bitPattern: ptr[chanSt + base]))
                            b0 = Float(Float16(bitPattern: ptr[2 * chanSt + base]))
                        } else if let ptr = rawPtr32 {
                            r0 = ptr[base]
                            g0 = ptr[chanSt + base]
                            b0 = ptr[2 * chanSt + base]
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
                onProgress(Double(tilesDone) / Double(totalTiles))
            }
        }

        if isCancelled() { return }

        // Normalise and write to UInt8 output
        for i in 0..<outW * outH {
            let w = max(accW[i], 1e-8)
            outputPixels[i * 4]     = UInt8(min(255, max(0, Int((accR[i] / w * 255).rounded()))))
            outputPixels[i * 4 + 1] = UInt8(min(255, max(0, Int((accG[i] / w * 255).rounded()))))
            outputPixels[i * 4 + 2] = UInt8(min(255, max(0, Int((accB[i] / w * 255).rounded()))))
        }
    }

    func cancelUpscale() {
        upscaleCancelled = true
    }

    func removeUpscaling() {
        removeEdit(.upscale)
    }
}
