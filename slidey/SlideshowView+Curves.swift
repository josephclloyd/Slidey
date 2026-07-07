import SwiftUI
import AppKit
import CoreImage

extension SlideshowView {

    @ViewBuilder var curvesHUD: some View {
        if showCurvesHUD {
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Text("Curves")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $curvesChannel) {
                            ForEach(CurveChannel.allCases, id: \.self) { ch in
                                Text(ch.rawValue).tag(ch)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    CurveGraphView(
                        points: curvePointsBinding,
                        channel: curvesChannel,
                        onChanged: { scheduleCurvesPreview() }
                    )
                    .frame(width: 280, height: 280)
                    HStack(spacing: 16) {
                        Button("Reset") {
                            curvesData[keyPath: curveChannelKeyPath] = .identity
                            scheduleCurvesPreview()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        Spacer()
                        Button("Cancel") { cancelCurvesHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyCurvesToImage() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .frame(maxWidth: 340)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    private var curveChannelKeyPath: WritableKeyPath<CurvesData, CurvePoints> {
        switch curvesChannel {
        case .all: return \.all
        case .red: return \.red
        case .green: return \.green
        case .blue: return \.blue
        }
    }

    private var curvePointsBinding: Binding<CurvePoints> {
        Binding(
            get: { curvesData[keyPath: curveChannelKeyPath] },
            set: { curvesData[keyPath: curveChannelKeyPath] = $0 }
        )
    }

    func openCurvesHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying else { return }
        curvesData = curvesURLLevels[url.absoluteString] ?? .init()
        curvesChannel = .all
        showCurvesHUD = true
        updateDisplayImage()
        curvesBaseImage = currentDisplayImage
        scheduleCurvesPreview()
    }

    func cancelCurvesHUD() {
        guard showCurvesHUD else { return }
        showCurvesHUD = false
        curvesTask?.cancel(); curvesTask = nil; curvesBaseImage = nil
        updateDisplayImage()
    }

    func applyCurvesToImage() {
        guard let url = imageLoader.currentImageURL else { cancelCurvesHUD(); return }
        if !curvesData.isIdentity {
            curvesURLLevels[url.absoluteString] = curvesData
        } else {
            curvesURLLevels.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showCurvesHUD = false
        curvesTask?.cancel(); curvesTask = nil; curvesBaseImage = nil
        updateDisplayImage()
    }

    func applyCurves(_ data: CurvesData, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var ciImage = CIImage(cgImage: cgImage)

        if !data.all.isIdentity {
            ciImage = applyToneCurve(data.all, to: ciImage)
        }
        if !data.red.isIdentity {
            ciImage = applyPerChannelCurve(data.red, channel: .red, to: ciImage)
        }
        if !data.green.isIdentity {
            ciImage = applyPerChannelCurve(data.green, channel: .green, to: ciImage)
        }
        if !data.blue.isIdentity {
            ciImage = applyPerChannelCurve(data.blue, channel: .blue, to: ciImage)
        }

        let ctx = CIContext()
        guard let cgOut = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    // MARK: - Private helpers

    private func scheduleCurvesPreview() {
        curvesTask?.cancel()
        curvesTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyCurvesPreview() }
        }
    }

    private func applyCurvesPreview() {
        guard let base = curvesBaseImage else { return }
        currentDisplayImage = (curvesData.isIdentity ? nil : applyCurves(curvesData, to: base)) ?? base
    }

    private func applyToneCurve(_ pts: CurvePoints, to ciImage: CIImage) -> CIImage {
        guard let f = CIFilter(name: "CIToneCurve") else { return ciImage }
        f.setValue(ciImage, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: pts.p0.x, y: pts.p0.y), forKey: "inputPoint0")
        f.setValue(CIVector(x: pts.p1.x, y: pts.p1.y), forKey: "inputPoint1")
        f.setValue(CIVector(x: pts.p2.x, y: pts.p2.y), forKey: "inputPoint2")
        f.setValue(CIVector(x: pts.p3.x, y: pts.p3.y), forKey: "inputPoint3")
        f.setValue(CIVector(x: pts.p4.x, y: pts.p4.y), forKey: "inputPoint4")
        return f.outputImage ?? ciImage
    }

    private enum RGBChannel { case red, green, blue }

    private func applyPerChannelCurve(
        _ pts: CurvePoints, channel: RGBChannel, to ciImage: CIImage
    ) -> CIImage {
        let rVec: CIVector
        let gVec: CIVector
        let bVec: CIVector
        switch channel {
        case .red:
            rVec = CIVector(x: 1, y: 0, z: 0, w: 0)
            gVec = CIVector(x: 1, y: 0, z: 0, w: 0)
            bVec = CIVector(x: 1, y: 0, z: 0, w: 0)
        case .green:
            rVec = CIVector(x: 0, y: 1, z: 0, w: 0)
            gVec = CIVector(x: 0, y: 1, z: 0, w: 0)
            bVec = CIVector(x: 0, y: 1, z: 0, w: 0)
        case .blue:
            rVec = CIVector(x: 0, y: 0, z: 1, w: 0)
            gVec = CIVector(x: 0, y: 0, z: 1, w: 0)
            bVec = CIVector(x: 0, y: 0, z: 1, w: 0)
        }

        guard let extract = CIFilter(name: "CIColorMatrix") else { return ciImage }
        extract.setValue(ciImage, forKey: kCIInputImageKey)
        extract.setValue(rVec, forKey: "inputRVector")
        extract.setValue(gVec, forKey: "inputGVector")
        extract.setValue(bVec, forKey: "inputBVector")
        extract.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        extract.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let grayChannel = extract.outputImage else { return ciImage }

        let curved = applyToneCurve(pts, to: grayChannel)

        let isolateR: CIVector
        let isolateG: CIVector
        let isolateB: CIVector
        let keepR: CIVector
        let keepG: CIVector
        let keepB: CIVector
        switch channel {
        case .red:
            isolateR = CIVector(x: 1, y: 0, z: 0, w: 0)
            isolateG = CIVector(x: 0, y: 0, z: 0, w: 0)
            isolateB = CIVector(x: 0, y: 0, z: 0, w: 0)
            keepR = CIVector(x: 0, y: 0, z: 0, w: 0)
            keepG = CIVector(x: 0, y: 1, z: 0, w: 0)
            keepB = CIVector(x: 0, y: 0, z: 1, w: 0)
        case .green:
            isolateR = CIVector(x: 0, y: 0, z: 0, w: 0)
            isolateG = CIVector(x: 0, y: 1, z: 0, w: 0)
            isolateB = CIVector(x: 0, y: 0, z: 0, w: 0)
            keepR = CIVector(x: 1, y: 0, z: 0, w: 0)
            keepG = CIVector(x: 0, y: 0, z: 0, w: 0)
            keepB = CIVector(x: 0, y: 0, z: 1, w: 0)
        case .blue:
            isolateR = CIVector(x: 0, y: 0, z: 0, w: 0)
            isolateG = CIVector(x: 0, y: 0, z: 0, w: 0)
            isolateB = CIVector(x: 0, y: 0, z: 1, w: 0)
            keepR = CIVector(x: 1, y: 0, z: 0, w: 0)
            keepG = CIVector(x: 0, y: 1, z: 0, w: 0)
            keepB = CIVector(x: 0, y: 0, z: 0, w: 0)
        }

        guard let isolate = CIFilter(name: "CIColorMatrix") else { return ciImage }
        isolate.setValue(curved, forKey: kCIInputImageKey)
        isolate.setValue(isolateR, forKey: "inputRVector")
        isolate.setValue(isolateG, forKey: "inputGVector")
        isolate.setValue(isolateB, forKey: "inputBVector")
        isolate.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        isolate.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let modifiedChannel = isolate.outputImage else { return ciImage }

        guard let keepOthers = CIFilter(name: "CIColorMatrix") else { return ciImage }
        keepOthers.setValue(ciImage, forKey: kCIInputImageKey)
        keepOthers.setValue(keepR, forKey: "inputRVector")
        keepOthers.setValue(keepG, forKey: "inputGVector")
        keepOthers.setValue(keepB, forKey: "inputBVector")
        keepOthers.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        keepOthers.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let otherChannels = keepOthers.outputImage else { return ciImage }

        guard let combine = CIFilter(name: "CIAdditionCompositing") else { return ciImage }
        combine.setValue(modifiedChannel, forKey: kCIInputImageKey)
        combine.setValue(otherChannels, forKey: kCIInputBackgroundImageKey)
        return combine.outputImage ?? ciImage
    }
}
