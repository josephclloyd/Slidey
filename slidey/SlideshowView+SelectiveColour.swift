import SwiftUI
import AppKit
import CoreImage

/// Per-image selective-colour settings: keep the hue within `width` degrees of
/// `hue` vivid, desaturate everything else to greyscale.
struct SelectiveColourSettings: Equatable {
    var hue: Double     // 0–360, centre of the kept hue range
    var width: Double   // 5–180, half-width tolerance around the centre
}

extension SlideshowView {

    @ViewBuilder var selectiveColourHUD: some View {
        if showSelectiveColourHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Selective Colour")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Circle()
                            .fill(Color(hue: selectiveColourHue / 360.0, saturation: 1, brightness: 1))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    HStack {
                        Text("Hue")
                            .foregroundColor(.white.opacity(0.8))
                        Slider(value: $selectiveColourHue, in: 0...360, step: 1)
                            .onChange(of: selectiveColourHue) { _, _ in scheduleSelectiveColourPreview() }
                            .tint(.white)
                            .accessibilityLabel("Kept hue")
                            .accessibilityValue(String(format: "%.0f degrees", selectiveColourHue))
                        Text(String(format: "%.0f\u{00B0}", selectiveColourHue))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    HStack {
                        Text("Range")
                            .foregroundColor(.white.opacity(0.8))
                        Slider(value: $selectiveColourWidth, in: 5...180, step: 1)
                            .onChange(of: selectiveColourWidth) { _, _ in scheduleSelectiveColourPreview() }
                            .tint(.white)
                            .accessibilityLabel("Hue range")
                            .accessibilityValue(String(format: "%.0f degrees", selectiveColourWidth))
                        Text(String(format: "%.0f\u{00B0}", selectiveColourWidth))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelSelectiveColourHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityHint("Discards the selective colour effect")
                        Button("Apply") { applySelectiveColourToImage() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Applies the selective colour effect to the image")
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

    func openSelectiveColourHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying, !showVignetteHUD, !showPerspectiveHUD,
              !showLocalAdjustmentsHUD, !showObjectRemovalHUD else { return }
        let existing = selectiveColourURLLevels[url.absoluteString]
        selectiveColourHue = existing?.hue ?? 0
        selectiveColourWidth = existing?.width ?? 30
        showSelectiveColourHUD = true
        updateDisplayImage()
        selectiveColourBaseImage = currentDisplayImage
        scheduleSelectiveColourPreview()
    }

    func cancelSelectiveColourHUD() {
        guard showSelectiveColourHUD else { return }
        showSelectiveColourHUD = false
        selectiveColourTask?.cancel()
        selectiveColourTask = nil
        selectiveColourBaseImage = nil
        updateDisplayImage()
    }

    func applySelectiveColourToImage() {
        guard let url = imageLoader.currentImageURL else { cancelSelectiveColourHUD(); return }
        registerUndoForEdit(url: url, actionName: "Selective Colour")
        selectiveColourURLLevels[url.absoluteString] =
            SelectiveColourSettings(hue: selectiveColourHue, width: selectiveColourWidth)
        saveFavourites()
        showSelectiveColourHUD = false
        selectiveColourTask?.cancel()
        selectiveColourTask = nil
        selectiveColourBaseImage = nil
        updateDisplayImage()
    }

    func removeSelectiveColourForCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        if showSelectiveColourHUD { cancelSelectiveColourHUD() }
        guard selectiveColourURLLevels[url.absoluteString] != nil else { return }
        registerUndoForEdit(url: url, actionName: "Remove Selective Colour")
        selectiveColourURLLevels.removeValue(forKey: url.absoluteString)
        saveFavourites()
        updateDisplayImage()
    }

    func applySelectiveColour(_ settings: SelectiveColourSettings, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let cubeData = Self.selectiveColourCubeData(hue: settings.hue, width: settings.width),
              let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(Self.selectiveColourCubeDimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        guard let outputImage = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgOut = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    // MARK: - Preview scheduling

    private func scheduleSelectiveColourPreview() {
        selectiveColourTask?.cancel()
        selectiveColourTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applySelectiveColourPreview() }
        }
    }

    private func applySelectiveColourPreview() {
        guard let base = selectiveColourBaseImage else { return }
        let settings = SelectiveColourSettings(hue: selectiveColourHue, width: selectiveColourWidth)
        currentDisplayImage = applySelectiveColour(settings, to: base) ?? base
    }

    // MARK: - Colour cube

    static let selectiveColourCubeDimension = 64

    /// Builds a `CIColorCube` lookup table that keeps colours whose hue lies within
    /// `width` degrees of `hue` and desaturates everything else to greyscale, with a
    /// short angular feather at the edge of the range for a smooth transition. All
    /// entries are finite and in [0, 1] by construction, so no NaN/Inf sanitising is
    /// required downstream.
    static func selectiveColourCubeData(hue: Double, width: Double) -> Data? {
        let size = selectiveColourCubeDimension
        let center = Float(hue)
        let halfWidth = Float(width)
        let feather: Float = 15
        var cube = [Float](repeating: 0, count: size * size * size * 4)
        var offset = 0
        // CIColorCube expects R varying fastest, then G, then B.
        for b in 0..<size {
            let bf = Float(b) / Float(size - 1)
            for g in 0..<size {
                let gf = Float(g) / Float(size - 1)
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1)
                    let mx = max(rf, max(gf, bf))
                    let mn = min(rf, min(gf, bf))
                    let delta = mx - mn
                    var pixelHue: Float = 0
                    if delta > 0 {
                        if mx == rf {
                            pixelHue = (gf - bf) / delta
                            if pixelHue < 0 { pixelHue += 6 }
                        } else if mx == gf {
                            pixelHue = (bf - rf) / delta + 2
                        } else {
                            pixelHue = (rf - gf) / delta + 4
                        }
                        pixelHue *= 60
                    }
                    let sat: Float = mx > 0 ? delta / mx : 0
                    var angular = abs(pixelHue - center)
                    if angular > 180 { angular = 360 - angular }
                    var keep: Float
                    if angular <= halfWidth {
                        keep = 1
                    } else if angular <= halfWidth + feather {
                        keep = 1 - (angular - halfWidth) / feather
                    } else {
                        keep = 0
                    }
                    // Near-grey pixels have no meaningful hue; leave them grey.
                    keep *= min(sat / 0.12, 1)
                    let lum = 0.299 * rf + 0.587 * gf + 0.114 * bf
                    cube[offset + 0] = lum + (rf - lum) * keep
                    cube[offset + 1] = lum + (gf - lum) * keep
                    cube[offset + 2] = lum + (bf - lum) * keep
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
