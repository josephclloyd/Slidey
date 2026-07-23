import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Pure, AVFoundation-free description of the frame sequence a slideshow video
/// export produces: each image is held for `holdFrames`, and consecutive images
/// are cross-faded over `transitionFrames` (zero when transitions are disabled,
/// giving a hard cut). Kept separate from the encoder so the frame ordering and
/// counts are unit-testable without touching AVFoundation.
struct SlideshowVideoFramePlan: Equatable {
    let imageCount: Int
    let holdFrames: Int
    let transitionFrames: Int

    /// A single output frame. `overlay == nil` is a plain hold frame showing
    /// `base`; otherwise `base` is cross-faded into `overlay` at `blend` (0…1).
    struct Frame: Equatable {
        let base: Int
        let overlay: Int?
        let blend: Double
    }

    var totalFrames: Int {
        guard imageCount > 0 else { return 0 }
        return imageCount * holdFrames + max(0, imageCount - 1) * transitionFrames
    }

    func frames() -> [Frame] {
        guard imageCount > 0 else { return [] }
        var result: [Frame] = []
        result.reserveCapacity(totalFrames)
        for i in 0..<imageCount {
            for _ in 0..<holdFrames {
                result.append(Frame(base: i, overlay: nil, blend: 0))
            }
            if i < imageCount - 1, transitionFrames > 0 {
                for f in 1...transitionFrames {
                    let blend = Double(f) / Double(transitionFrames)
                    result.append(Frame(base: i, overlay: i + 1, blend: blend))
                }
            }
        }
        return result
    }

    static func holdFrameCount(seconds: Double, fps: Int) -> Int {
        max(1, Int((seconds * Double(fps)).rounded()))
    }

    static func transitionFrameCount(enabled: Bool, duration: Double, fps: Int) -> Int {
        enabled ? max(1, Int((duration * Double(fps)).rounded())) : 0
    }
}

extension SlideshowView {

    // MARK: - HUD

    @ViewBuilder var videoExportHUD: some View {
        if showVideoExportHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Exporting Slideshow Video")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(videoExportProgress * 100))%")
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                    ProgressView(value: videoExportProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .accessibilityLabel("Video export progress")
                        .accessibilityValue("\(Int(videoExportProgress * 100)) percent")
                    HStack {
                        Spacer()
                        Button("Cancel") { cancelSlideshowVideoExport() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityHint("Stops the video export")
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

    // MARK: - Export driver

    private static let videoExportFPS: Int32 = 30
    private static let videoExportMaxLongEdge = 1920

    func startSlideshowVideoExport() {
        guard !showVideoExportHUD else { return }
        let urls = imageLoader.imageURLs
        guard !urls.isEmpty else {
            showErrorToast("No images to export")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Slideshow.mp4"
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            self.runVideoExport(urls: urls, destURL: destURL)
        }
    }

    func cancelSlideshowVideoExport() {
        videoExportCancellationToken?.cancel()
    }

    private func runVideoExport(urls: [URL], destURL: URL) {
        // Determine canvas size from the first image's aspect ratio (long edge
        // capped), so a homogeneous portrait/landscape set isn't over-letterboxed.
        // Rendering of each frame reads @State edit dictionaries, so it must hop
        // to the main thread; encoding runs on a background queue.
        guard let firstBase = imageLoader.decodedImage(for: urls[0]) else {
            showErrorToast("Could not read first image")
            return
        }
        let (canvasW, canvasH) = Self.canvasSize(for: firstBase.size)

        let transitions = transitionsEnabled
        let transitionDur = transitionDuration
        let holdSeconds = max(0.5, slideshowInterval)

        let token = TiledMLCancellationToken()
        videoExportCancellationToken = token
        videoExportProgress = 0
        showVideoExportHUD = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.encodeVideo(
                urls: urls, destURL: destURL,
                width: canvasW, height: canvasH,
                holdSeconds: holdSeconds,
                transitions: transitions, transitionDuration: transitionDur,
                token: token
            )
            DispatchQueue.main.async {
                self.showVideoExportHUD = false
                self.videoExportCancellationToken = nil
                self.videoExportProgress = 0
                switch result {
                case .success:
                    self.showSavedToast(filename: destURL.lastPathComponent)
                case .cancelled:
                    try? FileManager.default.removeItem(at: destURL)
                case .failure(let message):
                    try? FileManager.default.removeItem(at: destURL)
                    self.showErrorToast(message)
                }
            }
        }
    }

    private enum VideoExportResult {
        case success
        case cancelled
        case failure(String)
    }

    // MARK: - Encoding

    private func encodeVideo(
        urls: [URL], destURL: URL,
        width: Int, height: Int,
        holdSeconds: Double,
        transitions: Bool, transitionDuration: Double,
        token: TiledMLCancellationToken
    ) -> VideoExportResult {
        try? FileManager.default.removeItem(at: destURL)

        let fileType: AVFileType = destURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        guard let writer = try? AVAssetWriter(outputURL: destURL, fileType: fileType) else {
            return .failure("Could not create video writer")
        }

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: bufferAttributes
        )

        guard writer.canAdd(input) else { return .failure("Video writer rejected input") }
        writer.add(input)
        guard writer.startWriting() else {
            return .failure(writer.error?.localizedDescription ?? "Could not start writing")
        }
        writer.startSession(atSourceTime: .zero)

        let fps = Self.videoExportFPS
        let holdFrames = SlideshowVideoFramePlan.holdFrameCount(seconds: holdSeconds, fps: Int(fps))
        let transitionFrames = SlideshowVideoFramePlan.transitionFrameCount(
            enabled: transitions, duration: transitionDuration, fps: Int(fps)
        )
        let plan = SlideshowVideoFramePlan(
            imageCount: urls.count, holdFrames: holdFrames, transitionFrames: transitionFrames
        )
        let totalFrames = plan.totalFrames
        var frameIndex = 0

        func append(_ buffer: CVPixelBuffer) -> Bool {
            while !input.isReadyForMoreMediaData {
                if token.isCancelled { return false }
                usleep(5_000)
            }
            let time = CMTime(value: Int64(frameIndex), timescale: fps)
            let ok = adaptor.append(buffer, withPresentationTime: time)
            frameIndex += 1
            if totalFrames > 0 {
                let progress = min(1.0, Double(frameIndex) / Double(totalFrames))
                DispatchQueue.main.async { self.videoExportProgress = progress }
            }
            return ok
        }

        // Render one canvas-sized CGImage per URL on the main thread, carrying the
        // next-image render across the transition so it isn't recomputed twice.
        var current = canvasImage(for: urls[0], width: width, height: height)

        for i in 0..<urls.count {
            if token.isCancelled { writer.cancelWriting(); return .cancelled }

            let curImage = current
            for _ in 0..<holdFrames {
                if token.isCancelled { writer.cancelWriting(); return .cancelled }
                guard let buf = Self.makePixelBuffer(
                    base: curImage, overlay: nil, blend: 0,
                    pool: adaptor.pixelBufferPool, width: width, height: height
                ) else { writer.cancelWriting(); return .failure("Could not render video frame") }
                if !append(buf) {
                    if token.isCancelled { writer.cancelWriting(); return .cancelled }
                    writer.cancelWriting(); return .failure("Failed to append video frame")
                }
            }

            let isLast = i == urls.count - 1
            if !isLast {
                let next = canvasImage(for: urls[i + 1], width: width, height: height)
                if transitionFrames > 0 {
                    for f in 1...transitionFrames {
                        if token.isCancelled { writer.cancelWriting(); return .cancelled }
                        let t = Double(f) / Double(transitionFrames)
                        let eased = Self.easeInOut(t)
                        guard let buf = Self.makePixelBuffer(
                            base: curImage, overlay: next, blend: CGFloat(eased),
                            pool: adaptor.pixelBufferPool, width: width, height: height
                        ) else { writer.cancelWriting(); return .failure("Could not render transition frame") }
                        if !append(buf) {
                            if token.isCancelled { writer.cancelWriting(); return .cancelled }
                            writer.cancelWriting(); return .failure("Failed to append video frame")
                        }
                    }
                }
                current = next
            }
        }

        input.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        group.wait()

        if writer.status == .completed {
            return .success
        }
        return .failure(writer.error?.localizedDescription ?? "Video export failed")
    }

    /// Composites a single image (including per-URL edits) into a canvas-sized,
    /// letterboxed CGImage. Runs the edit pipeline on the main thread because it
    /// reads SwiftUI @State edit dictionaries.
    private func canvasImage(for url: URL, width: Int, height: Int) -> CGImage? {
        var rendered: CGImage?
        let work = {
            let base: NSImage?
            if url == self.imageLoader.currentImageURL {
                base = self.currentComposite(for: url) ?? self.imageLoader.decodedImage(for: url)
            } else {
                base = self.imageLoader.decodedImage(for: url)
            }
            guard let baseImage = base else { return }
            var edited = self.applyExportEdits(to: baseImage, for: url)
            if let angle = self.rotationAngles[url], angle != .zero {
                edited = self.applyRotation(edited, angle: angle)
            }
            guard let cg = edited.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            rendered = Self.letterbox(cg, width: width, height: height)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
        return rendered
    }

    // MARK: - Drawing helpers

    private static func canvasSize(for imageSize: CGSize) -> (Int, Int) {
        let w = max(1, imageSize.width)
        let h = max(1, imageSize.height)
        let longEdge = Double(videoExportMaxLongEdge)
        var outW: Double
        var outH: Double
        if w >= h {
            outW = longEdge
            outH = longEdge * Double(h / w)
        } else {
            outH = longEdge
            outW = longEdge * Double(w / h)
        }
        return (evenClamp(outW), evenClamp(outH))
    }

    private static func evenClamp(_ value: Double) -> Int {
        var v = Int(value.rounded())
        if v < 2 { v = 2 }
        if v % 2 != 0 { v += 1 }
        return v
    }

    private static func letterbox(_ cg: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let rect = aspectFitRect(imageSize: CGSize(width: cg.width, height: cg.height),
                                 into: CGSize(width: width, height: height))
        ctx.draw(cg, in: rect)
        return ctx.makeImage()
    }

    private static func aspectFitRect(imageSize: CGSize, into canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }

    private static func makePixelBuffer(
        base: CGImage?, overlay: CGImage?, blend: CGFloat,
        pool: CVPixelBufferPool?, width: Int, height: Int
    ) -> CVPixelBuffer? {
        guard let pool = pool else { return nil }
        var pbOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(.black)
        ctx.fill(full)
        if let base = base {
            ctx.setAlpha(1)
            ctx.draw(base, in: full)
        }
        if let overlay = overlay {
            ctx.setAlpha(blend)
            ctx.draw(overlay, in: full)
        }
        return pb
    }

    private static func easeInOut(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

