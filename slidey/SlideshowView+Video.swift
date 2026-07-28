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

    /// Fired each time the current video reaches the end (before it loops back
    /// to the start). The slideshow uses this to advance to the next file.
    var onPlayToEnd: (() -> Void)?

    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        stop()
        self.url = url
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

/// Thin AppKit bridge so the native macOS transport controls (scrubber, volume,
/// fullscreen) are available over the video.
struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

/// Full-viewport video display with a mute toggle and a subtle notice that the
/// image-editing tools don't apply to video.
struct VideoPlayerView: View {
    @Bindable var controller: VideoPlayerController
    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            VideoPlayerNSView(player: controller.player)

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
            VideoPlayerView(controller: videoController, url: url)
                .id(url)
                .onAppear {
                    DispatchQueue.main.async {
                        updateDisplayImage()
                        captureWindow()
                    }
                }
        } else {
            imageStillContent
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
