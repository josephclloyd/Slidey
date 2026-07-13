import SwiftUI
import AppKit
import CoreML

extension SlideshowView {

    @ViewBuilder var grainReductionHUD: some View {
        if showGrainReductionHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("AI Grain Reduction")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        if isReducingGrain {
                            Text("\(Int(grainReductionProgress * 100))%")
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text("\(Int(grainReductionStrength))%")
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    if isReducingGrain {
                        ProgressView(value: grainReductionProgress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                    } else {
                        Slider(value: $grainReductionStrength, in: 0...100, step: 1)
                            .onChange(of: grainReductionStrength) { _, _ in
                                DispatchQueue.main.async { updateGrainReductionBlend() }
                            }
                            .tint(.white)
                    }
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelGrainReductionHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyGrainReduction() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isReducingGrain)
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

    func removeGrainReduction() {
        removeEdit(.grainReduction)
    }

    func openGrainReductionHUD() {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing, !isCleaningJPEG, !isReducingGrain else { return }
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !showGrainReductionHUD else { return }

        grainReductionBaseImage = compositeBeforeStep(.grainReduction, for: url)
        grainReductionStrength = 100.0
        showGrainReductionHUD = true

        if let cached = grainReductionRawImages[url] {
            grainReductionMLImage = cached
            updateGrainReductionBlend()
        } else {
            runGrainReductionInference()
        }
    }

    func applyGrainReductionDirectly(strength: Double) {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts, !isColorizing, !isCleaningJPEG, !isReducingGrain else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = compositeBeforeStep(.grainReduction, for: url) else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isReducingGrain = true
        grainReductionProgress = 0
        let token = TiledMLCancellationToken()
        nafnetCancellationToken = token
        runTiledMLInference(srcCG: srcCG, source: source, label: "AI Grain Reduction", token: token,
                             config: TiledMLModelConfig(resourceName: "NAFNet_SIDD_width32", tileSize: 256, tileOverlap: 32, outputFeatureName: "denoised_image"),
                             progressHandler: { self.grainReductionProgress = $0 }) { mlImage in
            guard let mlImage else {
                self.isReducingGrain = false
                return
            }
            let blended = self.blendImages(base: source, overlay: mlImage, strength: strength / 100.0)
            self.grainReductionRawImages[url] = mlImage
            self.grainReducedImages[url] = blended
            self.clearCachesDownstream(of: .grainReduction, for: url)
            self.editStacks[url, default: EditStack()].append(.grainReduction(strength: strength))
            self.effectImages[url] = nil
            self.isReducingGrain = false
            self.saveFavourites()
            self.updateDisplayImage()
        }
    }

    private func runGrainReductionInference() {
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = grainReductionBaseImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isReducingGrain = true
        grainReductionProgress = 0
        let token = TiledMLCancellationToken()
        nafnetCancellationToken = token

        runTiledMLInference(srcCG: srcCG, source: source, label: "AI Grain Reduction", token: token,
                             config: TiledMLModelConfig(resourceName: "NAFNet_SIDD_width32", tileSize: 256, tileOverlap: 32, outputFeatureName: "denoised_image"),
                             progressHandler: { self.grainReductionProgress = $0 }) { mlImage in
            self.isReducingGrain = false
            guard let mlImage else {
                self.cancelGrainReductionHUD()
                return
            }
            guard self.imageLoader.currentImageURL == url, self.showGrainReductionHUD else { return }
            self.grainReductionMLImage = mlImage
            self.grainReductionRawImages[url] = mlImage
            self.updateGrainReductionBlend()
        }
    }

    func updateGrainReductionBlend() {
        guard let base = grainReductionBaseImage, let ml = grainReductionMLImage else { return }
        let strength = grainReductionStrength / 100.0
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

    func applyGrainReduction() {
        guard !isReducingGrain else { return }
        guard let url = imageLoader.currentImageURL,
              let result = currentDisplayImage else { cancelGrainReductionHUD(); return }
        grainReducedImages[url] = result
        clearCachesDownstream(of: .grainReduction, for: url)
        editStacks[url, default: EditStack()].append(.grainReduction(strength: grainReductionStrength))
        effectImages[url] = nil
        saveFavourites()
        showGrainReductionHUD = false
        grainReductionBaseImage = nil
        grainReductionMLImage = nil
        updateDisplayImage()
    }

    func cancelGrainReductionHUD() {
        guard showGrainReductionHUD else { return }
        nafnetCancellationToken?.cancel()
        nafnetCancellationToken = nil
        showGrainReductionHUD = false
        isReducingGrain = false
        grainReductionBaseImage = nil
        grainReductionMLImage = nil
        updateDisplayImage()
    }
}
