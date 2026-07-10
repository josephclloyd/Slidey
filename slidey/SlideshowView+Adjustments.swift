import SwiftUI
import AppKit
import CoreImage

extension SlideshowView {

    @ViewBuilder var adjustmentsHUD: some View {
        if showAdjustmentsHUD {
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Text("Adjustments")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { histogramShowRGB.toggle() }) {
                            Text(histogramShowRGB ? "RGB" : "L")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    if let data = histogramData {
                        HistogramView(data: data, showRGB: histogramShowRGB)
                            .frame(height: 60)
                    }
                    adjustmentRow("Exposure", value: $adjustments.exposure, range: -2...2)
                    adjustmentRow("Highlights", value: $adjustments.highlights, range: -1...1)
                    adjustmentRow("Shadows", value: $adjustments.shadows, range: -1...1)
                    adjustmentRow("Vibrance", value: $adjustments.vibrance, range: -1...1)
                    adjustmentRow("Warmth", value: $adjustments.warmth, range: -1...1)
                    HStack(spacing: 16) {
                        Button("Reset") {
                            adjustments = .init()
                            scheduleAdjustmentsPreview()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        Spacer()
                        Button("Cancel") { cancelAdjustmentsHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyAdjustmentsToImage() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .frame(maxWidth: 400)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    func adjustmentRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in scheduleAdjustmentsPreview() }
                .tint(.white)
            Text(String(format: "%+.2f", value.wrappedValue))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    func applyAdjustments(_ adj: ImageAdjustments, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var ciImage = CIImage(cgImage: cgImage)
        if adj.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adj.exposure, forKey: kCIInputEVKey)
            ciImage = f.outputImage ?? ciImage
        }
        if adj.highlights != 0 || adj.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(Float(1 - adj.highlights), forKey: "inputHighlightAmount")
            f.setValue(Float(adj.shadows + 0.5), forKey: "inputShadowAmount")
            ciImage = f.outputImage ?? ciImage
        }
        if adj.vibrance != 0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adj.vibrance, forKey: "inputAmount")
            ciImage = f.outputImage ?? ciImage
        }
        if adj.warmth != 0, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            let neutral = CIVector(x: 6500 + adj.warmth * 2000, y: 0)
            f.setValue(neutral, forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            ciImage = f.outputImage ?? ciImage
        }
        let ctx = CIContext()
        guard let cgOut = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    func openAdjustmentsHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying, !showPerspectiveHUD, !showLocalAdjustmentsHUD else { return }
        adjustments = adjustmentURLLevels[url.absoluteString] ?? .init()
        showAdjustmentsHUD = true
        updateDisplayImage()
        adjustmentsBaseImage = currentDisplayImage
        scheduleAdjustmentsPreview()
    }

    func scheduleAdjustmentsPreview() {
        adjustmentsTask?.cancel()
        adjustmentsTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyAdjustmentsPreview() }
        }
    }

    func applyAdjustmentsPreview() {
        guard let base = adjustmentsBaseImage else { return }
        let preview = (adjustments.isIdentity ? nil : applyAdjustments(adjustments, to: base)) ?? base
        currentDisplayImage = preview
        updateHistogram(from: preview)
    }

    func updateHistogram(from image: NSImage) {
        histogramData = HistogramData.compute(from: image)
    }

    func applyAdjustmentsToImage() {
        guard let url = imageLoader.currentImageURL else { cancelAdjustmentsHUD(); return }
        if !adjustments.isIdentity {
            adjustmentURLLevels[url.absoluteString] = adjustments
        } else {
            adjustmentURLLevels.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showAdjustmentsHUD = false
        adjustmentsTask?.cancel(); adjustmentsTask = nil; adjustmentsBaseImage = nil
        histogramData = nil
        updateDisplayImage()
    }

    func cancelAdjustmentsHUD() {
        guard showAdjustmentsHUD else { return }
        showAdjustmentsHUD = false
        adjustmentsTask?.cancel(); adjustmentsTask = nil; adjustmentsBaseImage = nil
        histogramData = nil
        updateDisplayImage()
    }
}
