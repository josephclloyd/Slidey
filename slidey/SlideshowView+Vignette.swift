import SwiftUI
import AppKit
import CoreImage

extension SlideshowView {

    @ViewBuilder var vignetteHUD: some View {
        if showVignetteHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Vignette")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.1f", vignetteIntensity))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                    Slider(value: $vignetteIntensity, in: 0...2, step: 0.1)
                        .onChange(of: vignetteIntensity) { _, _ in scheduleVignettePreview() }
                        .tint(.white)
                        .accessibilityLabel("Vignette intensity")
                        .accessibilityValue(String(format: "%.1f", vignetteIntensity))
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelVignetteHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityHint("Discards the vignette")
                        Button("Apply") { applyVignetteToImage() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Applies the vignette to the image")
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

    func openVignetteHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying, !showPerspectiveHUD, !showLocalAdjustmentsHUD, !showObjectRemovalHUD else { return }
        vignetteIntensity = vignetteURLLevels[url.absoluteString] ?? 1.0
        showVignetteHUD = true
        updateDisplayImage()
        vignetteBaseImage = currentDisplayImage
        scheduleVignettePreview()
    }

    func cancelVignetteHUD() {
        guard showVignetteHUD else { return }
        showVignetteHUD = false
        vignetteTask?.cancel()
        vignetteTask = nil
        vignetteBaseImage = nil
        updateDisplayImage()
    }

    func applyVignetteToImage() {
        guard let url = imageLoader.currentImageURL else { cancelVignetteHUD(); return }
        registerUndoForEdit(url: url, actionName: "Vignette")
        if vignetteIntensity > 0 {
            vignetteURLLevels[url.absoluteString] = vignetteIntensity
        } else {
            vignetteURLLevels.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showVignetteHUD = false
        vignetteTask?.cancel()
        vignetteTask = nil
        vignetteBaseImage = nil
        updateDisplayImage()
    }

    func applyVignette(intensity: Double, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIVignetteEffect") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: "inputCenter")
        filter.setValue(max(ciImage.extent.width, ciImage.extent.height) * 0.75, forKey: "inputRadius")
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        guard let outputImage = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgOut = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    // MARK: - Private helpers

    private func scheduleVignettePreview() {
        vignetteTask?.cancel()
        vignetteTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyVignettePreview() }
        }
    }

    private func applyVignettePreview() {
        guard let base = vignetteBaseImage else { return }
        currentDisplayImage = (vignetteIntensity > 0 ? applyVignette(intensity: vignetteIntensity, to: base) : nil) ?? base
    }
}
