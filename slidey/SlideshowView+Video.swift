import SwiftUI
import AVKit
import AVFoundation
import AppKit
import CoreImage

/// Non-destructive brightness/contrast/gamma applied to video playback (#342).
/// Identity is brightness 0, contrast 1, gamma 1 — the unmodified video.
struct VideoAdjustments: Equatable {
    var brightness: Double = 0   // CIColorControls inputBrightness, -1...1
    var contrast: Double = 1     // CIColorControls inputContrast, 0...2
    var gamma: Double = 1        // CIGammaAdjust inputPower, 0.25...4

    var isIdentity: Bool { brightness == 0 && contrast == 1 && gamma == 1 }
}

/// Owns the `AVPlayer` for inline video playback (#332). Videos start muted and
/// loop forever; `onPlayToEnd` fires at each loop boundary so the slideshow can
/// advance the same way animated GIFs do (see `SlideshowView+Animation.swift`).
@MainActor
@Observable
final class VideoPlayerController {
    let player = AVPlayer()
    private(set) var url: URL?
    private(set) var isPlaying = false
    var isMuted = true {
        didSet { player.isMuted = isMuted }
    }

    /// First frame decoded at the video's natural pixel size. Only used to give
    /// the zoom/pan math the true dimensions (scale-to-native, fill, pan clamp) —
    /// videos aren't `CGImageSource`-decodable so `ImageLoader.currentImage` is
    /// nil for them and can't supply those dimensions.
    private(set) var frameImage: NSImage?

    /// Fired each time the current video reaches the end (before it loops back
    /// to the start). The slideshow uses this to advance to the next file.
    var onPlayToEnd: (() -> Void)?

    /// Live brightness/contrast/gamma for the current video (#342). Setting this
    /// rebuilds and reassigns the player item's `videoComposition`, which forces
    /// the current frame to re-render even while paused. Persisted per-URL.
    var adjustments = VideoAdjustments() {
        didSet {
            guard adjustments != oldValue else { return }
            if let url { adjustmentsByURL[url] = adjustments }
            applyComposition()
        }
    }
    private var adjustmentsByURL: [URL: VideoAdjustments] = [:]

    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let target = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func load(url: URL) {
        stop()
        self.url = url
        loadFrameImage(for: url)
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onPlayToEnd?()
                // Loop: rewind and keep going.
                self.player.seek(to: .zero)
                if self.isPlaying { self.player.play() }
            }
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
        setupTimeObserver()
        // Restore per-URL adjustments and apply to the new item. Called
        // explicitly (not just via didSet) so a video whose stored values happen
        // to equal the outgoing video's still gets its composition wired up.
        adjustments = adjustmentsByURL[url] ?? VideoAdjustments()
        applyComposition()
        player.play()
        isPlaying = true
    }

    /// Rebuilds the CIFilter chain and assigns it to the current item. Identity
    /// adjustments clear the composition so playback runs unfiltered. Reassigning
    /// a fresh composition object re-renders the current frame even when paused.
    private func applyComposition() {
        guard let item = player.currentItem else { return }
        if adjustments.isIdentity {
            item.videoComposition = nil
            return
        }
        let adj = adjustments
        item.videoComposition = AVVideoComposition(
            asset: item.asset,
            applyingCIFiltersWithHandler: { request in
                let source = request.sourceImage.clampedToExtent()
                var output = source
                if let f = CIFilter(name: "CIColorControls") {
                    f.setValue(output, forKey: kCIInputImageKey)
                    f.setValue(adj.brightness, forKey: kCIInputBrightnessKey)
                    f.setValue(adj.contrast, forKey: kCIInputContrastKey)
                    output = f.outputImage ?? output
                }
                if adj.gamma != 1, let f = CIFilter(name: "CIGammaAdjust") {
                    f.setValue(output, forKey: kCIInputImageKey)
                    f.setValue(adj.gamma, forKey: "inputPower")
                    output = f.outputImage ?? output
                }
                request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
            }
        )
    }

    private func setupTimeObserver() {
        if let token = timeObserverToken { player.removeTimeObserver(token); timeObserverToken = nil }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let item = self.player.currentItem, item.status == .readyToPlay {
                    let d = CMTimeGetSeconds(item.duration)
                    if d.isFinite && d > 0 { self.duration = d }
                }
            }
        }
    }

    func stop() {
        if let token = timeObserverToken { player.removeTimeObserver(token); timeObserverToken = nil }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        onPlayToEnd = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        url = nil
        frameImage = nil
        currentTime = 0
        duration = 0
    }

    /// Decodes the natural-size first frame off the main thread and publishes it
    /// once ready. Zoom keys pressed before it lands are simply no-ops.
    private func loadFrameImage(for url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Self.fullFrameImage(url: url)
            DispatchQueue.main.async {
                guard self.url == url else { return }
                self.frameImage = image
            }
        }
    }

    nonisolated private static func fullFrameImage(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func togglePlayPause() {
        guard url != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func stepFrame(by count: Int) {
        player.currentItem?.step(byCount: count)
    }

    /// Returns the current video to its unmodified appearance and drops its saved
    /// per-URL adjustments so it reopens clean next time (#342).
    func resetAdjustments() {
        adjustments = VideoAdjustments()
        if let url { adjustmentsByURL.removeValue(forKey: url) }
    }
}

/// `AVPlayerView` subclass that:
/// - Reports mouse activity via `onControlsVisibilityChanged` so the SwiftUI
///   overlay can show/hide on mouse move and hide after 2.5 s idle. AVKit's
///   own controls stay at `.none` permanently — the SwiftUI layer owns the UI.
/// - Forwards magnify/scroll/drag gestures for zoom and pan.
/// - Intercepts all hit-testing when zoomed so the pan handler gets all events.
final class ZoomableAVPlayerView: AVPlayerView {
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onDragPan: ((CGFloat, CGFloat) -> Void)?
    /// Called with `true` when the overlay should appear, `false` when it should hide.
    var onControlsVisibilityChanged: ((Bool) -> Void)?
    var isZoomed: Bool = false {
        didSet {
            if isZoomed {
                hideControlsTimer?.invalidate()
                onControlsVisibilityChanged?(false)
            }
        }
    }

    private var hideControlsTimer: Timer?
    private var mouseTrackingArea: NSTrackingArea?

    // MARK: - Tracking area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = mouseTrackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { wakeControls() }
    override func mouseMoved(with event: NSEvent)   { wakeControls() }

    override func mouseExited(with event: NSEvent) {
        scheduleHide(after: 0.8)
    }

    private func wakeControls() {
        guard !isZoomed else { return }
        onControlsVisibilityChanged?(true)
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.onControlsVisibilityChanged?(false)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.onControlsVisibilityChanged?(false)
        }
    }

    // MARK: - Hit-testing and gestures

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isZoomed else { return super.hitTest(point) }
        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if !isZoomed { super.mouseDown(with: event) }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1.0 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onZoom?(1.0 + event.scrollingDeltaY * 0.005)
        } else {
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onDragPan?(event.deltaX, event.deltaY)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Thin AppKit bridge so the native macOS transport controls (scrubber, volume,
/// fullscreen) are available over the video, plus zoom/pan gesture forwarding.
struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    var isZoomed: Bool = false
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onDragPan: ((CGFloat, CGFloat) -> Void)?
    var onControlsVisibilityChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> ZoomableAVPlayerView {
        let view = ZoomableAVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        view.isZoomed = isZoomed
        view.onZoom = onZoom
        view.onScroll = onScroll
        view.onDragPan = onDragPan
        view.onControlsVisibilityChanged = onControlsVisibilityChanged
        return view
    }

    func updateNSView(_ nsView: ZoomableAVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        nsView.isZoomed = isZoomed
        nsView.onZoom = onZoom
        nsView.onScroll = onScroll
        nsView.onDragPan = onDragPan
        nsView.onControlsVisibilityChanged = onControlsVisibilityChanged
    }
}

/// Full-viewport video display with zoom/pan, a mute toggle, and a subtle notice
/// that the image-editing tools don't apply to video. Zoom/pan share the same
/// `ZoomPanController` state used for images, so it persists per-URL and all the
/// existing zoom keys route here when a video is active (#340).
struct VideoPlayerView: View {
    @Bindable var controller: VideoPlayerController
    let url: URL
    @Binding var zoomScale: CGFloat
    @Binding var imageOffset: CGSize
    let containerSize: CGSize
    /// Toggles the brightness/contrast/gamma panel (#342). The HUD is opened from
    /// this control rather than a key press so it stays discoverable and doesn't
    /// clash with the image-editing key registry.
    var onToggleAdjustments: (() -> Void)?
    /// Captures the current frame as a still image for editing (#341). On a button
    /// (not a key) for the same reason as the adjustments panel.
    var onCaptureFrame: (() -> Void)?

    @AppStorage("naturalScrollPan") private var naturalScrollPan: Bool = false
    @State private var overlayControlsVisible = false
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    var body: some View {
        ZStack {
            Color.black
            VideoPlayerNSView(
                player: controller.player,
                isZoomed: zoomScale > 1.0,
                onZoom: { applyZoom($0) },
                onScroll: { applyPan(dx: $0, dy: $1) },
                onDragPan: { applyDragPan(dx: $0, dy: $1) },
                onControlsVisibilityChanged: { visible in
                    withAnimation(.easeInOut(duration: 0.25)) { overlayControlsVisible = visible }
                }
            )
            .scaleEffect(zoomScale)
            .offset(imageOffset)
        }
        // Utility buttons (top-right) — editing keys are reserved for images.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button {
                    onToggleAdjustments?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Video adjustments")
                .accessibilityHint("Shows brightness, contrast, and gamma controls")

                Button {
                    onCaptureFrame?()
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture frame")
                .accessibilityHint("Grabs the current frame as an editable image")
            }
            .padding(14)
            .opacity(overlayControlsVisible ? 1 : 0)
        }
        // Transport bar (bottom) — play/pause, scrubber, time, mute.
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Button {
                    controller.stepFrame(by: -1)
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(controller.isPlaying ? .white.opacity(0.4) : .white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(controller.isPlaying)
                .accessibilityLabel("Previous frame")

                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")

                Button {
                    controller.stepFrame(by: 1)
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(controller.isPlaying ? .white.opacity(0.4) : .white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(controller.isPlaying)
                .accessibilityLabel("Next frame")

                Text(formatTime(controller.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 36, alignment: .trailing)

                Slider(value: $scrubPosition, in: 0...1) { editing in
                    isScrubbing = editing
                    if !editing { controller.seek(to: scrubPosition) }
                }
                .tint(.white)
                .onChange(of: controller.currentTime) { _, time in
                    guard !isScrubbing, controller.duration > 0 else { return }
                    scrubPosition = time / controller.duration
                }

                Text(formatTime(controller.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minWidth: 36, alignment: .leading)

                Button {
                    controller.toggleMute()
                } label: {
                    Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isMuted ? "Unmute video" : "Mute video")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .opacity(overlayControlsVisible ? 1 : 0)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let m = s / 60
        let h = m / 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m % 60, s % 60) }
        return String(format: "%d:%02d", m, s % 60)
    }

    // MARK: - Zoom / pan (mirrors ImageDisplayView's transform math)

    private func applyZoom(_ factor: CGFloat) {
        let oldScale = zoomScale
        let newScale = max(0.1, min(10.0, oldScale * factor))
        if newScale == oldScale { return }
        let actual = newScale / oldScale
        zoomScale = newScale
        imageOffset = CGSize(width: imageOffset.width * actual, height: imageOffset.height * actual)
        clampOffset()
    }

    private func applyPan(dx: CGFloat, dy: CGFloat) {
        let bounds = panBounds()
        guard bounds.x > 0 || bounds.y > 0 else { return }
        let sign: CGFloat = naturalScrollPan ? 1 : -1
        imageOffset.width += sign * dx
        imageOffset.height -= sign * dy
        clampOffset()
    }

    private func applyDragPan(dx: CGFloat, dy: CGFloat) {
        let bounds = panBounds()
        guard bounds.x > 0 || bounds.y > 0 else { return }
        imageOffset.width += dx
        imageOffset.height -= dy
        clampOffset()
    }

    private func clampOffset() {
        let bounds = panBounds()
        imageOffset.width = max(-bounds.x, min(bounds.x, imageOffset.width))
        imageOffset.height = max(-bounds.y, min(bounds.y, imageOffset.height))
    }

    private func panBounds() -> (x: CGFloat, y: CGFloat) {
        guard containerSize.width > 0, containerSize.height > 0 else { return (0, 0) }
        let natural: CGSize
        if let cg = controller.frameImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            natural = CGSize(width: cg.width, height: cg.height)
        } else if let ps = controller.player.currentItem?.presentationSize, ps.width > 0 {
            natural = ps
        } else {
            return (0, 0)
        }
        let fitScale = min(containerSize.width / natural.width, containerSize.height / natural.height)
        let displayed = CGSize(width: natural.width * fitScale * zoomScale, height: natural.height * fitScale * zoomScale)
        return (
            x: max(0, (displayed.width - containerSize.width) / 2),
            y: max(0, (displayed.height - containerSize.height) / 2)
        )
    }
}

extension ImageLoader {
    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Full-resolution frame at `time` from a video, oriented via the preferred
    /// track transform — the extraction half of Capture Frame (#341). Tolerance
    /// is zero so the returned frame matches the exact playback position the user
    /// sees. Pure and safe to call off the main thread; returns nil if the frame
    /// can't be extracted.
    nonisolated static func videoFrame(url: URL, at time: CMTime) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Filename for a captured video frame: `<video-basename>_frame_<MMmSSs>.jpg`
    /// (#341). Pure/testable; seconds are clamped to ≥ 0 and rounded.
    static func frameFilename(for videoURL: URL, seconds: Double) -> String {
        let base = videoURL.deletingPathExtension().lastPathComponent
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let stamp = String(format: "%02dm%02ds", total / 60, total % 60)
        return "\(base)_frame_\(stamp).jpg"
    }

    /// First-frame thumbnail for a video via `AVAssetImageGenerator`. Returns nil
    /// if the frame can't be extracted. Safe to call off the main thread.
    nonisolated static func videoThumbnail(url: URL, maxPixelSize: Int) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

extension SlideshowView {
    /// Swaps in the AVKit player for video files, otherwise the still-image view.
    @ViewBuilder var imageDisplayContent: some View {
        if isVideoActive, let url = imageLoader.currentImageURL {
            @Bindable var zoomPan = zoomPan
            GeometryReader { geometry in
                VideoPlayerView(
                    controller: videoController,
                    url: url,
                    zoomScale: $zoomPan.zoomScale,
                    imageOffset: $zoomPan.imageOffset,
                    containerSize: geometry.size,
                    onToggleAdjustments: { toggleVideoAdjustmentsHUD() },
                    onCaptureFrame: { captureCurrentVideoFrame() }
                )
                .id(url)
                .onAppear {
                    DispatchQueue.main.async {
                        zoomPan.windowSize = geometry.size
                        updateDisplayImage()
                        captureWindow()
                    }
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { _, newSize in
                    zoomPan.windowSize = newSize
                }
            }
        } else if capturedFrameURL != nil {
            imageStillContent
                .overlay(alignment: .top) { capturedFrameBar }
        } else {
            imageStillContent
        }
    }

    /// Toolbar shown over a captured video still (#341): save it beside the source
    /// video, or discard it and return to playback. The still is a normal editable
    /// image otherwise, so every image tool applies before saving.
    @ViewBuilder var capturedFrameBar: some View {
        HStack(spacing: 12) {
            Button {
                saveCapturedFrame()
            } label: {
                Label("Save Frame", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismissCapturedFrame()
            } label: {
                Label("Back to Video", systemImage: "chevron.backward")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: Capsule())
        .padding(.top, 16)
    }

    /// Live brightness/contrast/gamma panel for video (#342). Mutually exclusive
    /// with the image Adjustments HUD: this only opens when a video is active and
    /// `openAdjustmentsHUD()` only opens when a still image is loaded.
    @ViewBuilder var videoAdjustmentsHUD: some View {
        if showVideoAdjustmentsHUD {
            @Bindable var vc = videoController
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Text("Video Adjustments")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    videoAdjustmentRow("Brightness", value: $vc.adjustments.brightness, range: -1...1, format: "%+.2f")
                    videoAdjustmentRow("Contrast", value: $vc.adjustments.contrast, range: 0...2, format: "%.2f")
                    videoAdjustmentRow("Gamma", value: $vc.adjustments.gamma, range: 0.25...4, format: "%.2f")
                    HStack(spacing: 16) {
                        Button("Reset") { videoController.resetAdjustments() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .accessibilityHint("Returns the video to its unmodified appearance")
                        Spacer()
                        Button("Done") { closeVideoAdjustmentsHUD() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Closes the panel; adjustments stay applied to playback")
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

    func videoAdjustmentRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.white)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: format, value.wrappedValue))
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// Shows/hides the video adjustments panel from the on-video control. No-op
    /// unless a video is loaded (the button only appears over a video anyway).
    func toggleVideoAdjustmentsHUD() {
        guard isVideoActive, videoController.url != nil else { return }
        showVideoAdjustmentsHUD.toggle()
    }

    /// Hides the panel; the adjustments themselves persist on playback (and are
    /// stored per-URL in `VideoPlayerController`).
    func closeVideoAdjustmentsHUD() {
        showVideoAdjustmentsHUD = false
    }

    /// Saliency doesn't apply to video, so `z` (smart zoom) instead toggles the
    /// video between fit (aspect-fit, scale 1.0) and fill.
    func toggleVideoFitFill() {
        if activeZoomPan.zoomScale > 1.01 {
            activeZoomPan.reset()
        } else {
            activeZoomPan.zoomToFillScreen(image: activeZoomImage, rotationAngle: activeZoomRotation)
        }
    }

    /// True when the current file is a video that should render in the player
    /// rather than the still-image view. A captured still (#341) suppresses this
    /// so the frozen frame renders in the image view and inherits all edit tools.
    /// Arrow-key frame stepping when a video is paused and not zoomed.
    /// Returns `.handled` if the key was consumed, nil to fall through.
    func handleVideoFrameStepKey(_ key: KeyEquivalent) -> KeyPress.Result? {
        guard isVideoActive, !videoController.isPlaying, zoomPan.zoomScale <= 1.0 else { return nil }
        switch key {
        case .leftArrow:
            DispatchQueue.main.async { self.videoController.stepFrame(by: -1) }
            return .handled
        case .rightArrow:
            DispatchQueue.main.async { self.videoController.stepFrame(by: 1) }
            return .handled
        default:
            return nil
        }
    }

    var isVideoActive: Bool {
        guard capturedFrameURL == nil else { return false }
        guard let url = imageLoader.currentImageURL else { return false }
        return ImageLoader.isVideo(url)
    }

    /// Starts (or stops) inline video playback to match the current file. Called
    /// from `updateDisplayImage()`, mirroring `syncAnimation()`.
    func syncVideo() {
        guard let url = imageLoader.currentImageURL, ImageLoader.isVideo(url) else {
            stopVideoIfNeeded()
            return
        }
        if videoController.url == url { return }

        // A video is taking over the viewport: stop any running GIF animation.
        stopAnimationIfNeeded()

        let playingSlideshow = slideshow.isPlaying
        // Pause the fixed-interval timer while the video plays; end-of-playback
        // drives advancement instead (same approach as animated GIF).
        if playingSlideshow { slideshow.pause() }

        videoController.load(url: url)

        if playingSlideshow {
            let start = Date()
            let interval = slideshowInterval
            let advance = makeAdvanceClosure()
            let loopDisabled = !(UserDefaults.standard.object(forKey: "slideshowLoop") as? Bool ?? true)
            let atEnd = imageLoader.currentIndex >= imageLoader.imageURLs.count - 1
            videoController.onPlayToEnd = { [slideshow] in
                guard slideshow.isPlaying else { return }
                guard Date().timeIntervalSince(start) >= interval else { return }
                if loopDisabled && atEnd {
                    slideshow.stop()
                } else {
                    advance()
                }
            }
        }
    }

    func stopVideoIfNeeded() {
        guard videoController.url != nil else { return }
        showVideoAdjustmentsHUD = false
        videoController.stop()
        // Restore the fixed-interval timer we paused when the video started.
        if slideshow.isPlaying {
            slideshow.reschedule(interval: slideshowInterval, advance: makeAdvanceClosure())
        }
    }

    // MARK: - Capture Frame (#341)

    /// Captures the frame at the current playback position and shows it as a
    /// still, editable image in place of the video. The frame is held in memory
    /// (keyed by a synthetic `?frame=` URL) and only written to disk when the
    /// user chooses Save Frame, so it can be enhanced, cropped, upscaled, etc.
    /// first. Extraction runs off the main thread; the commit happens on main.
    func captureCurrentVideoFrame() {
        guard isVideoActive, let videoURL = imageLoader.currentImageURL else { return }
        let time = videoController.player.currentTime()
        let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
        DispatchQueue.global(qos: .userInitiated).async {
            let frame = ImageLoader.videoFrame(url: videoURL, at: time)
            DispatchQueue.main.async {
                // Bail if the user navigated away or already captured while we decoded.
                guard self.imageLoader.currentImageURL == videoURL, self.isVideoActive else { return }
                guard let frame else {
                    self.showErrorToast("Could not capture the current frame")
                    return
                }
                guard let synthetic = URL(string: videoURL.absoluteString + "?frame=\(seconds)") else {
                    self.showErrorToast("Could not capture the current frame")
                    return
                }
                self.videoController.player.pause()
                self.showVideoAdjustmentsHUD = false
                self.capturedFrameBase = frame
                self.capturedFrameURL = synthetic
                self.rotationAngle = .zero
                self.zoomPan.reset()
                // Routes through the captured-frame branch → setDisplay commit path.
                self.updateDisplayImage()
            }
        }
    }

    /// Writes the (possibly edited) captured frame to disk as a JPEG beside the
    /// source video, e.g. `myvideo_frame_00m12s.jpg`. Repeated saves don't
    /// overwrite — a numeric suffix is appended when the name is taken.
    func saveCapturedFrame() {
        guard let synthetic = capturedFrameURL, let videoURL = imageLoader.currentImageURL else { return }
        guard let image = currentDisplayImage ?? capturedFrameBase else {
            showErrorToast("No captured frame to save")
            return
        }
        let output = applyRotationIfNeeded(image)
        guard let data = encodeCapturedFrameJPEG(output) else {
            showErrorToast("Could not encode the captured frame")
            return
        }
        let filename = ImageLoader.frameFilename(for: videoURL, seconds: capturedFrameSeconds(from: synthetic))
        let outputURL = Self.uniqueFileURL(in: videoURL.deletingLastPathComponent(), preferred: filename)
        do {
            try data.write(to: outputURL)
            showSavedToast(filename: outputURL.lastPathComponent)
        } catch {
            showErrorToast("Frame save failed: \(error.localizedDescription)")
        }
    }

    /// Discards the captured still and returns to video playback.
    func dismissCapturedFrame() {
        clearCapturedFrame()
        rotationAngle = .zero
        updateDisplayImage()
        if isVideoActive { videoController.player.play() }
    }

    /// Drops the captured still and every edit-state entry keyed to its synthetic
    /// URL, so a fresh capture always starts clean and nothing lingers in the
    /// per-URL caches once the frame is gone.
    func clearCapturedFrame() {
        guard let url = capturedFrameURL else { return }
        let key = url.absoluteString
        editStacks[url] = nil
        enhancedImages[url] = nil; smoothedImages[url] = nil; sharpenedImages[url] = nil
        upscaledImages[url] = nil; upscaleFactors[url] = nil
        faceRestoredImages[url] = nil; redEyedImages[url] = nil
        backgroundRemovedImages[url] = nil; artifactRemovedImages[url] = nil
        jpegCleanedImages[url] = nil; jpegCleanupRawImages[url] = nil
        colorizedImages[url] = nil
        grainReducedImages[url] = nil; grainReductionRawImages[url] = nil
        objectRemovedImages[url] = nil
        effectImages[url] = nil; imageEffects[url] = nil
        rotationAngles[url] = nil
        adjustmentURLLevels[key] = nil; curvesURLLevels[key] = nil; vignetteURLLevels[key] = nil
        straightenAngles[key] = nil; perspectiveCorners[key] = nil; cropRegions[key] = nil
        localAdjustmentURLLayers[key] = nil
        flippedHorizontally.remove(key); flippedVertically.remove(key)
        capturedFrameURL = nil
        capturedFrameBase = nil
    }

    /// The seconds payload from a synthetic `<video>?frame=<seconds>` URL.
    func capturedFrameSeconds(from synthetic: URL) -> Double {
        let value = URLComponents(url: synthetic, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "frame" })?.value
        return Double(value ?? "") ?? 0
    }

    /// Window-title text for a captured still: the filename it would save as.
    func capturedFrameTitle(for synthetic: URL) -> String {
        guard let videoURL = imageLoader.currentImageURL else { return synthetic.lastPathComponent }
        return ImageLoader.frameFilename(for: videoURL, seconds: capturedFrameSeconds(from: synthetic))
    }

    /// The URL that edit commands should apply to. In compare mode with the
    /// right pane selected this is `compareURL`; otherwise the current image.
    var editTargetURL: URL? {
        if showCompareMode && compareActiveSide == .right { return compareURL }
        if let capturedFrameURL { return capturedFrameURL }
        return imageLoader.currentImageURL
    }

    /// The un-edited decoded base bitmap for a URL. Uses the loader's live
    /// current-image cache when `url` is the current image, otherwise decodes
    /// the file directly (needed for editing the right compare pane).
    func baseImage(for url: URL) -> NSImage? {
        if url == capturedFrameURL { return capturedFrameBase }
        return url == imageLoader.currentImageURL ? imageLoader.currentImage : imageLoader.decodedImage(for: url)
    }

    /// Composite path for a captured video still (#341): rebuilds the display from
    /// the synthetic-URL edit stack via the shared `setDisplay` commit path.
    func updateCapturedFrameDisplay() {
        guard let capturedURL = capturedFrameURL else { return }
        if let base = currentComposite(for: capturedURL) ?? capturedFrameBase {
            setDisplay(base: base, for: capturedURL)
        }
    }

    private func encodeCapturedFrameJPEG(_ image: NSImage, quality: CGFloat = 0.92) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// A non-colliding URL in `dir` for `preferred`, inserting ` 2`, ` 3`, … before
    /// the extension if a file already exists so repeated captures never clobber.
    static func uniqueFileURL(in dir: URL, preferred: String) -> URL {
        let fm = FileManager.default
        let first = dir.appendingPathComponent(preferred)
        guard fm.fileExists(atPath: first.path) else { return first }
        let stem = (preferred as NSString).deletingPathExtension
        let ext = (preferred as NSString).pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
