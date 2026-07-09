import SwiftUI
import AppKit
import CoreImage

extension SlideshowView {

    @ViewBuilder var straightenHUD: some View {
        if showStraightenHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Straighten")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%+.1f\u{00b0}", straightenAngle))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Slider(value: $straightenAngle, in: -15...15, step: 0.1)
                        .onChange(of: straightenAngle) { _, _ in scheduleStraightenPreview() }
                        .tint(.white)
                    HStack(spacing: 16) {
                        Button("Reset") {
                            straightenAngle = 0
                            scheduleStraightenPreview()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        Spacer()
                        Button("Cancel") { cancelStraightenHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyStraightenToImage() }
                            .buttonStyle(.borderedProminent)
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

    func openStraightenHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying, !showPerspectiveHUD else { return }
        straightenAngle = straightenAngles[url.absoluteString] ?? 0.0
        showStraightenHUD = true
        updateDisplayImage()
        straightenBaseImage = currentDisplayImage
        scheduleStraightenPreview()
    }

    func cancelStraightenHUD() {
        guard showStraightenHUD else { return }
        showStraightenHUD = false
        straightenTask?.cancel()
        straightenTask = nil
        straightenBaseImage = nil
        updateDisplayImage()
    }

    func applyStraightenToImage() {
        guard let url = imageLoader.currentImageURL else { cancelStraightenHUD(); return }
        if straightenAngle != 0 {
            straightenAngles[url.absoluteString] = straightenAngle
        } else {
            straightenAngles.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showStraightenHUD = false
        straightenTask?.cancel()
        straightenTask = nil
        straightenBaseImage = nil
        updateDisplayImage()
    }

    func removeStraightenForCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        straightenAngles.removeValue(forKey: url.absoluteString)
        saveFavourites()
        updateDisplayImage()
    }

    func applyStraightenTransform(angle: Double, to image: NSImage) -> NSImage? {
        guard angle != 0 else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let radians = CGFloat(angle * .pi / 180.0)

        let w = ciImage.extent.width
        let h = ciImage.extent.height
        let transform = CGAffineTransform.identity
            .translatedBy(x: w / 2, y: h / 2)
            .rotated(by: radians)
            .translatedBy(x: -w / 2, y: -h / 2)
        let rotated = ciImage.transformed(by: transform)

        let absAngle = abs(radians)
        let sinA = sin(absAngle)
        let cosA = cos(absAngle)
        let cropW = w * cosA - h * sinA
        let cropH = h * cosA - w * sinA

        let ctx = CIContext()
        if cropW > 0, cropH > 0 {
            let cropRect = CGRect(
                x: rotated.extent.midX - cropW / 2,
                y: rotated.extent.midY - cropH / 2,
                width: cropW,
                height: cropH
            )
            let cropped = rotated.cropped(to: cropRect)
            guard let cgOut = ctx.createCGImage(cropped, from: cropped.extent) else { return nil }
            return NSImage(cgImage: cgOut, size: NSSize(width: cropW, height: cropH))
        }

        guard let cgOut = ctx.createCGImage(rotated, from: rotated.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: NSSize(width: rotated.extent.width, height: rotated.extent.height))
    }

    // MARK: - Private helpers

    private func scheduleStraightenPreview() {
        straightenTask?.cancel()
        straightenTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyStraightenPreview() }
        }
    }

    private func applyStraightenPreview() {
        guard let base = straightenBaseImage else { return }
        if straightenAngle == 0 {
            currentDisplayImage = base
        } else {
            currentDisplayImage = applyStraightenTransform(angle: straightenAngle, to: base) ?? base
        }
    }
}
