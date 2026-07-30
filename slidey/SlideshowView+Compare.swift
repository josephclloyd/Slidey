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
        compareManualPin = false
        compareZoomPan.reset()
        zoomPan.reset()
        slideshow.stop()
        showBeforeAfterSlider = false
        showCompareMode = true
    }

    /// Opens the thumbnail picker sheet for choosing any image in the active
    /// (filtered) set as the right compare pane. Distinct from ⌥B, which pins
    /// the next image for speed.
    func openComparePicker() {
        guard imageLoader.imageURLs.count >= 2 else {
            showErrorToast("Need at least two images to compare")
            return
        }
        comparePickerShowing = true
    }

    /// Loads the picked image into the right pane and enters compare mode with
    /// the current image on the left. The pane is manually pinned, so navigating
    /// the left pane will not auto-repin the right pane to the next image.
    func setCompareRightPane(_ url: URL) {
        comparePickerShowing = false
        compareURL = url
        compareImage = compareComposite(for: url)
        compareRotation = rotationAngles[url] ?? .zero
        compareActiveSide = .left
        compareManualPin = true
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
        case KeyEquivalent("S"):          // ⇧S — toggle pan/zoom sync between the two panes
            toggleCompareSync(); return .handled
        default:
            // Fall through so edit key bindings still fire in compare mode;
            // they route to the active pane via `editTargetURL`.
            return nil
        }
    }

    /// Called from onCurrentIndexChanged to keep the right pane in sync when
    /// the user navigates while compare mode is active.
    func updateComparePaneIfNeeded() {
        guard showCompareMode, !compareManualPin,
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
        compareManualPin = false
        compareSyncEnabled = false
        compareZoomPan.reset()
    }

    /// Toggles pane pan/zoom sync. Sync does not force the panes into alignment
    /// on toggle (no jump); it only mirrors changes made by the *next* gesture.
    func toggleCompareSync() {
        compareSyncEnabled.toggle()
        let message = compareSyncEnabled ? "Pane sync on" : "Pane sync off"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if savedToast == message { savedToast = nil }
        }
    }

    /// Mirrors the source pane's zoom/pan onto the target when sync is enabled.
    /// The value-equality check — not a transient flag — is what breaks the
    /// feedback loop: SwiftUI's `onChange` fires in a later update cycle, so a
    /// flag set-then-cleared within this call is already clear by the time the
    /// target's own `onChange` re-enters here. Because we only assign when the
    /// values differ, the re-entrant call finds them equal and stops.
    func syncComparePanes(from source: ZoomPanController, to target: ZoomPanController) {
        guard compareSyncEnabled,
              let synced = Self.syncedPaneState(
                  source: (source.zoomScale, source.imageOffset),
                  target: (target.zoomScale, target.imageOffset))
        else { return }
        target.zoomScale = synced.scale
        target.imageOffset = synced.offset
    }

    /// Pure helper: the zoom/pan the target should adopt to mirror the source,
    /// or nil if the panes already match (no propagation needed).
    static func syncedPaneState(
        source: (scale: CGFloat, offset: CGSize),
        target: (scale: CGFloat, offset: CGSize)
    ) -> (scale: CGFloat, offset: CGSize)? {
        if target.scale == source.scale && target.offset == source.offset { return nil }
        return (source.scale, source.offset)
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
        .onChange(of: zoomPan.zoomScale) { _, _ in syncComparePanes(from: zoomPan, to: compareZoomPan) }
        .onChange(of: zoomPan.imageOffset) { _, _ in syncComparePanes(from: zoomPan, to: compareZoomPan) }
        .onChange(of: compareZoomPan.zoomScale) { _, _ in syncComparePanes(from: compareZoomPan, to: zoomPan) }
        .onChange(of: compareZoomPan.imageOffset) { _, _ in syncComparePanes(from: compareZoomPan, to: zoomPan) }
        .overlay(alignment: .top) {
            if compareSyncEnabled {
                Text("Pan/zoom synced")
                    .font(.caption).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
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

    @State private var borderVisible = true
    @State private var fadeTimer: Timer?

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
            .clipped()
            .overlay {
                if isActive && borderVisible {
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                guard isActive else { return }
                switch phase {
                case .active:
                    borderVisible = true
                    resetFadeTimer()
                case .ended:
                    resetFadeTimer()
                @unknown default:
                    break
                }
            }
            .onChange(of: isActive) { _, newVal in
                if newVal {
                    borderVisible = true
                    resetFadeTimer()
                } else {
                    fadeTimer?.invalidate()
                    fadeTimer = nil
                }
            }
            .onAppear { zoomPan.windowSize = geo.size }
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _, newSize in
                zoomPan.windowSize = newSize
            }
        }
    }

    private func resetFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            DispatchQueue.main.async { borderVisible = false }
        }
    }
}

/// Sheet for choosing any image in the active (filtered) set as the right
/// compare pane. Reuses the thumbnail-grid pattern (`LazyVGrid` + `ThumbnailCell`)
/// from the contact-sheet grid. The current image (left pane) is highlighted.
struct ComparePickerSheet: View {
    @ObservedObject var imageLoader: ImageLoader
    var favouriteURLStrings: Set<String> = []
    let currentURL: URL?
    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    private let thumbSize: CGFloat = 140
    private let spacing: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize), spacing: spacing)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose an image to compare")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(Array(imageLoader.imageURLs.enumerated()), id: \.element) { pair in
                        ThumbnailCell(
                            url: pair.element,
                            size: thumbSize,
                            isSelected: pair.element == currentURL,
                            isFavourite: favouriteURLStrings.contains(pair.element.absoluteString),
                            onTap: { onSelect(pair.element) }
                        )
                    }
                }
                .padding(spacing)
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .accessibilityLabel("Compare picker, \(imageLoader.imageURLs.count) images")
    }
}
