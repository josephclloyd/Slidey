import SwiftUI
import AVKit
import AVFoundation
import AppKit

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

    private var endObserver: NSObjectProtocol?

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
        player.play()
        isPlaying = true
    }

    func stop() {
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
}

/// `AVPlayerView` subclass that forwards magnify / scroll / drag gestures for
/// zoom and pan while leaving normal clicks to reach the floating transport
/// controls (scrubber, volume) — those live in subviews, so only gestures on
/// the video body itself hit these overrides.
final class ZoomableAVPlayerView: AVPlayerView {
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onDragPan: ((CGFloat, CGFloat) -> Void)?

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
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onDragPan: ((CGFloat, CGFloat) -> Void)?

    func makeNSView(context: Context) -> ZoomableAVPlayerView {
        let view = ZoomableAVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        view.onZoom = onZoom
        view.onScroll = onScroll
        view.onDragPan = onDragPan
        return view
    }

    func updateNSView(_ nsView: ZoomableAVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        nsView.onZoom = onZoom
        nsView.onScroll = onScroll
        nsView.onDragPan = onDragPan
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

    @AppStorage("naturalScrollPan") private var naturalScrollPan: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            VideoPlayerNSView(
                player: controller.player,
                onZoom: { applyZoom($0) },
                onScroll: { applyPan(dx: $0, dy: $1) },
                onDragPan: { applyDragPan(dx: $0, dy: $1) }
            )
            .scaleEffect(zoomScale)
            .offset(imageOffset)

            // `m` is bound to smoothing for images, so mute lives on a button.
            Button {
                controller.toggleMute()
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel(controller.isMuted ? "Unmute video" : "Mute video")
        }
        .overlay(alignment: .bottomLeading) {
            Text("Editing not available for video")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(14)
        }
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
        guard let cg = controller.frameImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              containerSize.width > 0, containerSize.height > 0 else {
            return (0, 0)
        }
        let natural = CGSize(width: cg.width, height: cg.height)
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
                    containerSize: geometry.size
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
        } else {
            imageStillContent
        }
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
    /// rather than the still-image view.
    var isVideoActive: Bool {
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
        videoController.stop()
        // Restore the fixed-interval timer we paused when the video started.
        if slideshow.isPlaying {
            slideshow.reschedule(interval: slideshowInterval, advance: makeAdvanceClosure())
        }
    }
}
