import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decodes and plays animated GIFs / APNGs by cycling frames on a per-frame
/// timer. Frames are pre-decoded (off the main thread) into an array of
/// `NSImage`; the timer advances `currentFrame`, which the view observes.
///
/// Playback loops forever. `onLoopComplete` fires at every loop boundary so the
/// slideshow can decide whether to advance (it only advances once the slide has
/// been shown for at least the configured interval — see `startAnimation`).
@Observable
final class AnimationPlayer {
    private(set) var currentFrame: NSImage?
    private(set) var isPlaying = false
    private(set) var url: URL?

    /// Fired at each loop boundary (after the last frame wraps to the first).
    var onLoopComplete: (() -> Void)?

    private var frames: [NSImage] = []
    private var delays: [Double] = []
    private var index = 0
    private var timer: Timer?

    deinit { timer?.invalidate() }

    func start(url: URL, frames: [NSImage], delays: [Double]) {
        stop()
        guard frames.count > 1, frames.count == delays.count else { return }
        self.url = url
        self.frames = frames
        self.delays = delays
        self.index = 0
        self.currentFrame = frames[0]
        self.isPlaying = true
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        url = nil
        frames = []
        delays = []
        index = 0
        onLoopComplete = nil
    }

    private func scheduleNext() {
        let delay = delays[index]
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        guard isPlaying else { return }
        let next = index + 1
        if next >= frames.count {
            index = 0
            currentFrame = frames[0]
            scheduleNext()
            onLoopComplete?()
        } else {
            index = next
            currentFrame = frames[next]
            scheduleNext()
        }
    }
}

/// Detection + frame decoding for animated images. Pure functions, safe to call
/// off the main thread.
enum AnimationDecoder {
    /// Upper bound on frame count we pre-decode. Beyond this we treat the image
    /// as static rather than risk holding a very large array of decoded bitmaps.
    static let maxFrames = 500

    /// GIF89a minimum frame delay. A 0s / near-0s delay means "as fast as the
    /// renderer allows", which browsers clamp to ~10fps — we do the same.
    static let minDelay: Double = 0.1

    static func isAnimated(url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 1,
              let type = CGImageSourceGetType(source) as String?,
              let ut = UTType(type) else { return false }
        return ut.conforms(to: .gif) || ut.conforms(to: .png)
    }

    static func decode(url: URL) -> (frames: [NSImage], delays: [Double])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= maxFrames,
              let type = CGImageSourceGetType(source) as String?,
              let ut = UTType(type),
              ut.conforms(to: .gif) || ut.conforms(to: .png) else { return nil }
        let isPNG = ut.conforms(to: .png)

        var frames: [NSImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let size = NSSize(width: cg.width, height: cg.height)
            frames.append(NSImage(cgImage: cg, size: size))
            delays.append(frameDelay(source: source, index: i, isPNG: isPNG))
        }
        guard frames.count > 1 else { return nil }
        return (frames, delays)
    }

    private static func frameDelay(source: CGImageSource, index: Int, isPNG: Bool) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return minDelay
        }
        let dictKey = isPNG ? kCGImagePropertyPNGDictionary : kCGImagePropertyGIFDictionary
        let unclampedKey = isPNG ? kCGImagePropertyAPNGUnclampedDelayTime : kCGImagePropertyGIFUnclampedDelayTime
        let clampedKey = isPNG ? kCGImagePropertyAPNGDelayTime : kCGImagePropertyGIFDelayTime
        guard let frameProps = props[dictKey] as? [CFString: Any] else { return minDelay }
        if let unclamped = frameProps[unclampedKey] as? Double, unclamped > 0 {
            return max(unclamped, minDelay)
        }
        if let clamped = frameProps[clampedKey] as? Double, clamped > 0 {
            return max(clamped, minDelay)
        }
        return minDelay
    }
}

extension SlideshowView {
    /// The image to render: the current animation frame when one is playing (and
    /// not suppressed), otherwise the composited/original static image.
    var activeDisplayImage: NSImage? {
        if animator.isPlaying, !isAnimationSuppressed, let frame = animator.currentFrame {
            return frame
        }
        return showingOriginal ? imageLoader.currentImage : currentDisplayImage
    }

    /// True when an interactive HUD, edit preview, or alternate display mode is
    /// active — animation is frozen in those cases so the static frame the user
    /// is editing (or comparing) is what shows.
    var isAnimationSuppressed: Bool {
        showAdjustmentsHUD || showCurvesHUD || showVignetteHUD || showStraightenHUD ||
        showPerspectiveHUD || showDenoiseHUD || showJPEGCleanupHUD || showGrainReductionHUD ||
        showLocalAdjustmentsHUD || showObjectRemovalHUD || showVideoExportHUD || showMetadataEditor ||
        cropController.isActive || showCompareMode || showBeforeAfterSlider || showingOriginal || isProcessing
    }

    /// An image is "pristine" (eligible for animation) only when it carries no
    /// committed edits of any kind — otherwise we show the composited static
    /// frame produced by `updateDisplayImage()` instead.
    func isPristine(for url: URL) -> Bool {
        let key = url.absoluteString
        if let stack = editStacks[url], !stack.isEmpty { return false }
        if let angle = rotationAngles[url], angle != .zero { return false }
        if flippedHorizontally.contains(key) || flippedVertically.contains(key) { return false }
        if imageEffects[url] != nil { return false }
        if let layers = localAdjustmentURLLayers[key], !layers.isEmpty { return false }
        if let adj = adjustmentURLLevels[key], !adj.isIdentity { return false }
        if let curves = curvesURLLevels[key], !curves.isIdentity { return false }
        if let vignette = vignetteURLLevels[key], vignette > 0 { return false }
        if selectiveColourURLLevels[key] != nil { return false }
        if let straighten = straightenAngles[key], straighten != 0 { return false }
        if perspectiveCorners[key] != nil { return false }
        if cropRegions[key] != nil { return false }
        return true
    }

    /// Central entry point, called at the end of `updateDisplayImage()`. Starts
    /// animation for a pristine animated image, or stops any running animation
    /// when the current image is edited, suppressed, or not animated.
    func syncAnimation() {
        guard !isAnimationSuppressed,
              let url = imageLoader.currentImageURL,
              isPristine(for: url) else {
            stopAnimationIfNeeded()
            return
        }
        // Already animating (or mid-decode of) this image — nothing to do.
        if animator.url == url || pendingAnimationURL == url { return }

        stopAnimationIfNeeded()
        guard AnimationDecoder.isAnimated(url: url) else { return }

        pendingAnimationURL = url
        DispatchQueue.global(qos: .userInitiated).async {
            let decoded = AnimationDecoder.decode(url: url)
            DispatchQueue.main.async {
                guard self.pendingAnimationURL == url else { return }
                self.pendingAnimationURL = nil
                guard self.imageLoader.currentImageURL == url,
                      !self.isAnimationSuppressed,
                      self.isPristine(for: url),
                      let decoded, decoded.frames.count > 1 else { return }
                self.startAnimation(url: url, frames: decoded.frames, delays: decoded.delays)
            }
        }
    }

    private func startAnimation(url: URL, frames: [NSImage], delays: [Double]) {
        let playingSlideshow = slideshow.isPlaying
        // While a slideshow is running, pause its fixed-interval timer and let the
        // animation drive advancement instead (after one full loop, and no sooner
        // than the configured interval so short GIFs don't race by).
        if playingSlideshow { slideshow.pause() }

        animator.start(url: url, frames: frames, delays: delays)

        if playingSlideshow {
            let start = Date()
            let interval = slideshowInterval
            let advance = makeAdvanceClosure()
            let loopDisabled = !(UserDefaults.standard.object(forKey: "slideshowLoop") as? Bool ?? true)
            let atEnd = imageLoader.currentIndex >= imageLoader.imageURLs.count - 1
            animator.onLoopComplete = { [slideshow] in
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

    func stopAnimationIfNeeded() {
        pendingAnimationURL = nil
        guard animator.isPlaying || animator.url != nil else { return }
        animator.stop()
        // Restore the slideshow's fixed-interval timer we paused when the
        // animation started.
        if slideshow.isPlaying {
            slideshow.reschedule(interval: slideshowInterval, advance: makeAdvanceClosure())
        }
    }
}
