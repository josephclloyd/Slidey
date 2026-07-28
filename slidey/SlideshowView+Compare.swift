import SwiftUI
import AppKit

/// Which pane in compare mode is the active target for edit commands.
enum CompareSide { case left, right }

extension SlideshowView {
    /// The index of the image shown in the second (right) compare pane: the
    /// next image in the current filtered set, wrapping around to the first.
    /// Returns nil when there are fewer than two images to compare.
    static func compareTargetIndex(current: Int, count: Int) -> Int? {
        guard count >= 2 else { return nil }
        return (current + 1) % count
    }

    /// Toggles the side-by-side comparison view. On enter it pins the next
    /// image in the directory into the right pane; ⌥B or Escape exits.
    func toggleCompareMode() {
        if showCompareMode {
            exitCompareMode()
            return
        }
        guard let targetIndex = Self.compareTargetIndex(
            current: imageLoader.currentIndex,
            count: imageLoader.imageURLs.count
        ) else {
            showErrorToast("Need at least two images to compare")
            return
        }
        let targetURL = imageLoader.imageURLs[targetIndex]
        compareURL = targetURL
        compareImage = compareComposite(for: targetURL)
        compareRotation = rotationAngles[targetURL] ?? .zero
        compareActiveSide = .left
        compareZoomPan.reset()
        zoomPan.reset()
        slideshow.stop()
        showBeforeAfterSlider = false
        showCompareMode = true
    }

    /// Composites the direct (non-HUD) edits for a compare-pane URL onto its
    /// decoded base: the cached edit-stack steps plus flip and photo effect.
    /// Rotation is applied by the pane's own binding, not baked in here.
    func compareComposite(for url: URL) -> NSImage? {
        let stack = editStacks[url] ?? EditStack()
        var result = baseImage(for: url)
        for step in stack.steps {
            if let cached = cachedImage(for: step, url: url) { result = cached } else { break }
        }
        let isFlippedH = flippedHorizontally.contains(url.absoluteString)
        let isFlippedV = flippedVertically.contains(url.absoluteString)
        if (isFlippedH || isFlippedV), let base = result {
            result = applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: base) ?? base
        }
        if let effectName = imageEffects[url], let base = result {
            result = applyPhotoEffect(effectName, to: base) ?? base
        }
        return result
    }

    /// Recomputes the right pane's image after an edit commits to it.
    func refreshCompareImage() {
        guard let url = compareURL else { return }
        compareImage = compareComposite(for: url)
    }

    /// Handles key presses that are valid in compare mode. Returns nil when
    /// compare mode is not active (caller should continue normal handling).
    func handleCompareModeKeyPress(_ key: KeyEquivalent) -> KeyPress.Result? {
        guard showCompareMode else { return nil }
        switch key {
        case .escape:
            exitCompareMode(); return .handled
        case .leftArrow:
            DispatchQueue.main.async { self.imageLoader.previousImage() }; return .handled
        case .rightArrow:
            DispatchQueue.main.async { self.imageLoader.nextImage() }; return .handled
        case KeyEquivalent("B"):          // ⇧B — switch from compare mode to before/after slider
            toggleBeforeAfterSlider(); return .handled
        default:
            // Fall through so edit key bindings still fire in compare mode;
            // they route to the active pane via `editTargetURL`.
            return nil
        }
    }

    /// Called from onCurrentIndexChanged to keep the right pane in sync when
    /// the user navigates while compare mode is active.
    func updateComparePaneIfNeeded() {
        guard showCompareMode,
              let targetIndex = Self.compareTargetIndex(
                  current: imageLoader.currentIndex,
                  count: imageLoader.imageURLs.count)
        else { return }
        let targetURL = imageLoader.imageURLs[targetIndex]
        compareURL = targetURL
        compareImage = compareComposite(for: targetURL)
        compareRotation = rotationAngles[targetURL] ?? .zero
        compareZoomPan.reset()
    }

    func exitCompareMode() {
        showCompareMode = false
        compareImage = nil
        compareURL = nil
        compareActiveSide = .left
        compareZoomPan.reset()
    }

    /// Static 50/50 horizontal split: current image on the left, pinned next
    /// image on the right, each with its own independent zoom/pan/rotation.
    @ViewBuilder var compareModeContent: some View {
        HStack(spacing: 0) {
            ComparePaneView(image: effectiveDisplayImage, url: imageLoader.currentImageURL,
                            zoomPan: zoomPan, rotation: $rotationAngle,
                            showFilename: showFilename,
                            isActive: compareActiveSide == .left,
                            onSelect: { compareActiveSide = .left })
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1)
            ComparePaneView(image: compareImage, url: compareURL,
                            zoomPan: compareZoomPan, rotation: $compareRotation,
                            showFilename: showFilename,
                            isActive: compareActiveSide == .right,
                            onSelect: { compareActiveSide = .right })
        }
    }
}

/// One half of the comparison split: a fitted image with independent
/// zoom/pan (via mouse gestures) plus a filename caption. A left-click selects
/// the pane as the active edit target rather than navigating; the active pane
/// is marked with a thin accent-colour border.
struct ComparePaneView: View {
    let image: NSImage?
    let url: URL?
    @Bindable var zoomPan: ZoomPanController
    @Binding var rotation: Angle
    var showFilename: Bool = false
    var isActive: Bool = false
    var onSelect: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let image {
                    ImageDisplayView(
                        image: image,
                        zoomScale: $zoomPan.zoomScale,
                        imageOffset: $zoomPan.imageOffset,
                        containerSize: geo.size,
                        rotationAngle: $rotation,
                        onLeftClick: onSelect,
                        onRightClick: {},
                        dragURL: url,
                        swipeEnabled: false
                    )
                } else {
                    ProgressView()
                }

                if showFilename, let url {
                    VStack {
                        Spacer()
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.bottom, 14)
                    }
                }
            }
            .overlay {
                if isActive {
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { zoomPan.windowSize = geo.size }
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _, newSize in
                zoomPan.windowSize = newSize
            }
        }
    }
}
