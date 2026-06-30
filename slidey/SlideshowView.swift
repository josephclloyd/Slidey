import SwiftUI
import AppKit
import CoreImage
import CoreML
import IOKit.pwr_mgt
import Vision
import UniformTypeIdentifiers

func validateRenameTarget(newName: String, ext: String, directory: URL, originalBasename: String) -> String? {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed == originalBasename { return nil }
    if trimmed.contains("/") || trimmed.contains(":") {
        return "Name cannot contain \"/\" or \":\" characters"
    }
    let targetPath = directory.appendingPathComponent("\(trimmed).\(ext)").path
    if FileManager.default.fileExists(atPath: targetPath) {
        return "A file named \"\(trimmed).\(ext)\" already exists"
    }
    return nil
}

struct ImageInfo {
    let width: Int
    let height: Int
    let fileSizeText: String
    let dateTakenText: String
    let cameraText: String?
}

private final class OpenWithMenuDelegate: NSObject {
    static var current: OpenWithMenuDelegate?  // keep alive through synchronous popup

    let imageURL: URL
    init(imageURL: URL) { self.imageURL = imageURL }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open([imageURL], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

struct SlideshowView: View {
    @StateObject private var imageLoader = ImageLoader()
    @StateObject private var musicManager = MusicManager()

    @EnvironmentObject var recentDirectories: RecentDirectories
    @EnvironmentObject var pendingOpens: PendingOpens
    @State private var showSongPicker = false
    @State private var showPlaylistPicker = false

    @State private var selectedDirectory: URL?
    @State private var scopedDirectory: URL?
    @State private var isFullScreen = false
    @State private var zoomPan = ZoomPanController()
    @State private var rotationAngle: Angle = .zero
    @State private var rotationAngles: [URL: Angle] = [:]
    @State private var lastDisplayedURL: URL?
    @State private var windowTitle: String = "Slidey"
    @State private var enhancedImages: [URL: NSImage] = [:]
    @State private var smoothedImages: [URL: NSImage] = [:]
    @State private var sharpenedImages: [URL: NSImage] = [:]
    @State private var upscaledImages: [URL: NSImage] = [:]
    @State private var upscaleFactors: [URL: Int] = [:]
    @State private var activeUpscaleScale: Int = 4
    @State private var savedZoomScales: [URL: CGFloat] = [:]
    @State private var savedPanOffsets: [URL: CGSize] = [:]
    @State private var currentDisplayImage: NSImage?
    @State private var myWindow: NSWindow?
    @State private var windowHasFocus = false
    @State private var isProcessing = false
    @State private var debugOutput = ""
    @State private var showDebugWindow = false
    @State private var showFilename = false
    @State private var upscaleCancelled = false
    @State private var upscaleProgress: Double = 0
    @State private var isDragOver = false
    @State private var slideshow = SlideshowController()
    @State private var savedToast: String?
    @State private var savedToastIsError: Bool = false
    @State private var showThumbnails = false
    @State private var infoOverlayURLs: Set<URL> = []
    @State private var imageInfoCache: [URL: ImageInfo] = [:]
    @State private var displaySleepAssertionID: IOPMAssertionID = 0
    @State private var hasDisplaySleepAssertion = false
    @AppStorage("slideshowInterval") private var slideshowInterval: Double = 5
    @AppStorage("sortOrder") private var sortOrder: AppSortOrder = .creationDateAscending
    @AppStorage("autoOpenRecent") private var autoOpenRecent: Bool = true
    @AppStorage("autoPlayMusic") private var autoPlayMusic: Bool = true
    @AppStorage("transitionsEnabled") private var transitionsEnabled: Bool = false
    @AppStorage("transitionDuration") private var transitionDuration: Double = 0.3
    @AppStorage("slideshowLoop") private var slideshowLoop: Bool = true
    @AppStorage("floatAboveOtherWindows") private var floatAboveOtherWindows: Bool = false
    @State private var isAutoOpening = false
    @State private var showKeyboardShortcuts = false
    @State private var favouriteURLStrings: Set<String> = []
    @State private var enhancedURLStrings: Set<String> = []
    @State private var smoothedURLStrings: Set<String> = []
    @State private var sharpenedURLStrings: Set<String> = []
    @State private var denoiseURLLevels: [String: Double] = [:]
    @State private var showDenoiseHUD: Bool = false
    @State private var denoiseLevel: Double = 50.0
    @State private var denoiseBaseImage: NSImage?
    @State private var denoiseTask: Task<Void, Never>?
    @State private var imageEffects: [URL: String] = [:]      // active CIPhotoEffect* name per URL
    @State private var effectImages: [URL: NSImage] = [:]      // cached effect-applied images
    @State private var flippedHorizontally: Set<String> = []
    @State private var flippedVertically: Set<String> = []
    @State private var vignetteURLLevels: [String: Double] = [:]
    @State private var showVignetteHUD: Bool = false
    @State private var vignetteIntensity: Double = 1.0
    @State private var vignetteBaseImage: NSImage?
    @State private var vignetteTask: Task<Void, Never>?

    struct ImageAdjustments: Codable, Equatable {
        var exposure: Double = 0
        var highlights: Double = 0
        var shadows: Double = 0
        var vibrance: Double = 0
        var warmth: Double = 0
        var isIdentity: Bool {
            exposure == 0 && highlights == 0 && shadows == 0 && vibrance == 0 && warmth == 0
        }
    }
    @State private var adjustmentURLLevels: [String: ImageAdjustments] = [:]
    @State private var showAdjustmentsHUD: Bool = false
    @State private var adjustments: ImageAdjustments = .init()
    @State private var adjustmentsBaseImage: NSImage?
    @State private var adjustmentsTask: Task<Void, Never>?
    @State private var smartZoomEnabled: Bool = false
    @State private var saliencyRects: [URL: CGRect] = [:]
    @State private var showFavouritesOnly: Bool = false
    @State private var isCursorHidden = false
    @State private var mouseMonitor: Any?
    @State private var keyUpMonitor: Any?
    @State private var cursorShowTask: Task<Void, Never>?
    @State private var showingOriginal: Bool = false
    @State private var faceRestoredImages: [URL: NSImage] = [:]
    @State private var isFaceRestoring = false
    @State private var faceRestoreProgress: Double = 0
    @State private var showNoFaceAlert = false
    @State private var redEyedImages: [URL: NSImage] = [:]
    @State private var backgroundRemovedImages: [URL: NSImage] = [:]
    @State private var artifactRemovedImages: [URL: NSImage] = [:]
    @State private var isRemovingArtifacts = false
    @State private var artifactRemovalProgress: Double = 0

    private var effectiveDisplayImage: NSImage? {
        currentDisplayImage ?? imageLoader.currentImage
    }

    private var imageAccessibilityLabel: String {
        guard let url = imageLoader.currentImageURL else { return "No image" }
        let name = url.lastPathComponent
        let position = "image \(imageLoader.currentIndex + 1) of \(imageLoader.imageURLs.count)"
        if let dims = Self.imageDimensions(for: url) {
            return "\(name), \(dims.width) by \(dims.height) pixels, \(position)"
        }
        return "\(name), \(position)"
    }

    @ViewBuilder
    private var emptyStateContent: some View {
        if isAutoOpening {
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading…")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading images")
            .onAppear {
                DispatchQueue.main.async { captureWindow() }
            }
        } else if showFavouritesOnly && imageLoader.hasUnfilteredImages {
            VStack(spacing: 20) {
                Text("★")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.5))
                Text("No favourites in this directory")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                Text("Press x to favourite images, then v to filter")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
            }
            .onAppear {
                DispatchQueue.main.async { captureWindow() }
            }
        } else {
            VStack(spacing: 30) {
                Text("Welcome to Slidey")
                    .font(.largeTitle)
                    .foregroundColor(.white)

                HStack(spacing: 40) {
                    VStack(spacing: 20) {
                        Button("Select Directory") {
                            selectDirectory()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens a folder picker to choose an image directory")
                    }

                    if !recentDirectories.directories.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Recent Directories")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(recentDirectories.directories) { entry in
                                    Button(action: {
                                        openRecent(entry)
                                    }) {
                                        HStack {
                                            Image(systemName: "folder.fill")
                                                .foregroundColor(.blue)
                                            Text(entry.displayName)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .frame(width: 250)
                                        .padding(8)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open \(entry.displayName)")
                                    .accessibilityHint("Opens this recent directory")
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async { captureWindow() }
            }
        }
    }

    @ViewBuilder private var denoiseHUD: some View {
        if showDenoiseHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Denoise")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(denoiseLevel))%")
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Slider(value: $denoiseLevel, in: 0...100, step: 1)
                        .onChange(of: denoiseLevel) { _, _ in DispatchQueue.main.async { scheduleDenoisePreview() } }
                        .tint(.white)
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelDenoise() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyDenoise() }
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

    @ViewBuilder private var vignetteHUD: some View {
        if showVignetteHUD {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        Text("Vignette")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.1f", vignetteIntensity))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Slider(value: $vignetteIntensity, in: 0...2, step: 0.1)
                        .onChange(of: vignetteIntensity) { _, _ in scheduleVignettePreview() }
                        .tint(.white)
                    HStack(spacing: 16) {
                        Button("Cancel") { cancelVignetteHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyVignetteToImage() }
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

    @ViewBuilder private var adjustmentsHUD: some View {
        if showAdjustmentsHUD {
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    Text("Adjustments")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    adjustmentRow("Exposure", value: $adjustments.exposure, range: -2...2)
                    adjustmentRow("Highlights", value: $adjustments.highlights, range: -1...1)
                    adjustmentRow("Shadows", value: $adjustments.shadows, range: -1...1)
                    adjustmentRow("Vibrance", value: $adjustments.vibrance, range: -1...1)
                    adjustmentRow("Warmth", value: $adjustments.warmth, range: -1...1)
                    HStack(spacing: 16) {
                        Button("Reset") {
                            adjustments = .init()
                            scheduleAdjustmentsPreview()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        Spacer()
                        Button("Cancel") { cancelAdjustmentsHUD() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Apply") { applyAdjustmentsToImage() }
                            .buttonStyle(.borderedProminent)
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

    private func adjustmentRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in scheduleAdjustmentsPreview() }
                .tint(.white)
            Text(String(format: "%+.2f", value.wrappedValue))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var overlayViews: some View {
        // Thumbnail strip overlay (bottom)
        if showThumbnails && !imageLoader.imageURLs.isEmpty {
            VStack {
                Spacer()
                ThumbnailStrip(imageLoader: imageLoader, favouriteURLStrings: favouriteURLStrings) { index in
                    guard !isProcessing else { return }
                    imageLoader.jumpTo(index: index)
                }
            }
        }

        // Filename + counter overlay
        if showFilename, let url = imageLoader.currentImageURL {
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 12) {
                        Text(favouriteURLStrings.contains(url.absoluteString) ? "★ \(url.lastPathComponent)" : url.lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                        let counter = "\(imageLoader.currentIndex + 1) / \(imageLoader.imageURLs.count)"
                        Text(showFavouritesOnly ? "★ \(counter)" : counter)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
                    Spacer()
                }
            }
        }

        // Image info overlay (top-left)
        if let url = imageLoader.currentImageURL,
           infoOverlayURLs.contains(url),
           let info = imageInfoCache[url] {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let upscaled = upscaledImages[url] {
                            let upW = Int(upscaled.size.width)
                            let upH = Int(upscaled.size.height)
                            Text("\(info.width) \u{00d7} \(info.height) px \u{2192} \(upW) \u{00d7} \(upH) px")
                        } else {
                            Text("\(info.width) \u{00d7} \(info.height) px")
                        }
                        Text(info.fileSizeText)
                        Text(info.dateTakenText)
                        if let camera = info.cameraText {
                            Text(camera)
                        }
                        if let factor = upscaleFactors[url] {
                            Text("Upscaled \(factor)\u{00d7}")
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    Spacer()
                }
                Spacer()
            }
        }

        // Save confirmation / error toast (lower-right)
        if let savedToast {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(savedToast)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((savedToastIsError ? Color.red : Color.green).opacity(0.85))
                        .cornerRadius(6)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
            .transition(.opacity)
        }

        // Track info overlay (top-right, shown briefly on track change)
        if musicManager.showTrackOverlay, let title = musicManager.currentTrackTitle {
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(title)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.white)
                        if let artist = musicManager.currentTrackArtist {
                            Text(artist)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                }
                Spacer()
            }
            .transition(.opacity)
        }

        directoryMissingOverlay

        // Progress indicator overlay
        if isProcessing {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("AI Upscaling Image (\(activeUpscaleScale)x)…")
                        .font(.headline)
                        .foregroundColor(.white)

                    ProgressView(value: upscaleProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                        .accessibilityLabel("Upscale progress")
                        .accessibilityValue("\(Int(upscaleProgress * 100)) percent")

                    Text("\(Int(upscaleProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .accessibilityHidden(true)

                    Button("Cancel", action: cancelUpscale)
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityLabel("Cancel upscaling")
                        .accessibilityHint("Stops the AI upscaling process")
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        if isFaceRestoring {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("Restoring Faces\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView(value: faceRestoreProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                    Text("\(Int(faceRestoreProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        if isRemovingArtifacts {
            VStack {
                Spacer()
                VStack(spacing: 15) {
                    Text("Removing Artifacts\u{2026}")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView(value: artifactRemovalProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)
                    Text("\(Int(artifactRemovalProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(30)
                .background(.black.opacity(0.85))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }

        // Debug window overlay (toggle with 'd' key)
        if showDebugWindow {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Upscaling Debug Output")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Close") {
                            showDebugWindow = false
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Close debug window")
                    }

                    ScrollView {
                        Text(debugOutput)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 300)

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.white)
                    }
                }
                .padding(20)
                .background(.black.opacity(0.9))
                .cornerRadius(12)
                .frame(width: 700)
                .padding(.bottom, 40)
            }
        }

        denoiseHUD
        vignetteHUD
        adjustmentsHUD

        // Before/After: "Original" label shown while holding b
        if showingOriginal {
            VStack {
                Text("Original")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.7))
                    .cornerRadius(6)
                    .padding(.top, 20)
                Spacer()
            }
        }
    }


    @ViewBuilder private var imageDisplayContent: some View {
        @Bindable var zoomPan = zoomPan
        GeometryReader { geometry in
            let displayedImage = showingOriginal ? imageLoader.currentImage : currentDisplayImage
            if let image = displayedImage {
                ImageDisplayView(
                    image: image,
                    zoomScale: $zoomPan.zoomScale,
                    imageOffset: $zoomPan.imageOffset,
                    containerSize: geometry.size,
                    rotationAngle: $rotationAngle,
                    onLeftClick: {
                        guard !isProcessing else { return }
                        imageLoader.nextImage()
                    },
                    onRightClick: {
                        guard !isProcessing else { return }
                        imageLoader.previousImage()
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(imageAccessibilityLabel)
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: "Next image") { imageLoader.nextImage() }
                .accessibilityAction(named: "Previous image") { imageLoader.previousImage() }
                .id(imageLoader.currentImageURL)
                .transition(.opacity)
                .onAppear {
                    // Defer mutations: .id() causes this onAppear to fire synchronously
                    // within the parent view's render pass (not after it).
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
        }
        .animation(transitionsEnabled ? .easeInOut(duration: transitionDuration) : nil, value: imageLoader.currentImageURL)
    }

    private var coreView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if imageLoader.imageURLs.isEmpty {
                emptyStateContent
            } else {
                imageDisplayContent
            }

            overlayViews
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 4)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: imageLoader.imageURLs.isEmpty) { _, isEmpty in
            DispatchQueue.main.async { onImageURLsEmptyChanged(isEmpty) }
        }
        .onChange(of: imageLoader.imageURLs) { _, newURLs in
            // Drop any per-URL session state for files that no longer exist
            // in the directory (deleted on disk, or we switched folders).
            DispatchQueue.main.async { onImageURLsChanged(newURLs) }
        }
        .onChange(of: imageLoader.currentIndex) { _, _ in
            // Defer mutations to after the view update to suppress
            // "Publishing changes from within view updates" warnings from @Observable.
            DispatchQueue.main.async { onCurrentIndexChanged() }
        }
        .onChange(of: isFullScreen) { _, fullScreen in
            updateCursorVisibility()
            if fullScreen {
                acquireDisplaySleepAssertion()
            } else {
                releaseDisplaySleepAssertion()
                musicManager.deactivate()
            }
        }
        .onChange(of: floatAboveOtherWindows) { _, newValue in
            myWindow?.level = newValue ? .floating : .normal
        }
        .onChange(of: myWindow) { _, window in
            if let window = window, floatAboveOtherWindows {
                window.level = .floating
            }
        }
        .onChange(of: showThumbnails) { _, _ in
            updateCursorVisibility()
        }
        .onChange(of: slideshow.isPlaying) { _, isPlaying in
            cursorShowTask?.cancel()
            updateCursorVisibility()
            if isPlaying { cancelDenoise(); cancelVignetteHUD(); cancelAdjustmentsHUD() }
        }
        .onChange(of: sortOrder) { _, newValue in
            imageLoader.sortOrder = newValue
            if !imageLoader.imageURLs.isEmpty {
                imageLoader.applySort()
            }
        }
        .onAppear {
            imageLoader.sortOrder = sortOrder
            loadFavourites()
            consumePendingOpenIfPossible()
            scheduleAutoOpenRecent()
            startMouseMonitor()
        }
        .onDisappear {
            slideshow.stop()
            releaseDisplaySleepAssertion()
            musicManager.deactivate()
            stopMouseMonitor()
            if isCursorHidden {
                NSCursor.unhide()
                isCursorHidden = false
            }
            NSApplication.shared.presentationOptions = []
        }
        .onChange(of: pendingOpens.pending) { _, _ in
            consumePendingOpenIfPossible()
        }
        .onChange(of: isProcessing) { _, isP in
            if isP {
                slideshow.stop()
            } else {
                consumePendingOpenIfPossible()
            }
        }
        .onChange(of: imageLoader.directoryMissing) { _, missing in
            DispatchQueue.main.async {
                if missing {
                    slideshow.stop()
                    showErrorToast("Directory moved or deleted")
                } else {
                    let message = "Directory restored"
                    savedToast = message
                    savedToastIsError = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if savedToast == message { savedToast = nil }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    var body: some View {
        coreView
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.selectDirectory)) { _ in
            ifKeyWindow { selectDirectory() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.openDirectory)) { notification in
            if let entry = notification.object as? RecentDirectory {
                ifKeyWindow { openRecent(entry) }
            }
        }
        .onChange(of: windowTitle) { _, newTitle in
            updateWindowTitle(newTitle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.enhanceImage)) { _ in
            ifKeyWindow { enhanceCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeEnhancement)) { _ in
            ifKeyWindow { removeEnhancement() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.scaleToNative)) { _ in
            ifKeyWindow { zoomPan.zoomToNativeSize(image: effectiveDisplayImage, rotationAngle: rotationAngle) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.scaleToFill)) { _ in
            ifKeyWindow { zoomPan.zoomToFillScreen(image: effectiveDisplayImage, rotationAngle: rotationAngle) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.rotateClockwise)) { _ in
            ifKeyWindow { rotateClockwise() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.rotateCounterClockwise)) { _ in
            ifKeyWindow { rotateCounterClockwise() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.smoothImage)) { _ in
            ifKeyWindow { smoothCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeSmoothing)) { _ in
            ifKeyWindow { removeSmoothing() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.sharpenImage)) { _ in
            ifKeyWindow { sharpenCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeSharpening)) { _ in
            ifKeyWindow { removeSharpening() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.denoiseImage)) { _ in
            ifKeyWindow { openDenoiseHUD() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.applyPhotoEffect)) { note in
            ifKeyWindow { setPhotoEffect(note.object as? String) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleSmartZoom)) { _ in
            ifKeyWindow { toggleSmartZoom() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.flipHorizontal)) { _ in
            ifKeyWindow { flipCurrentImageHorizontal() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.flipVertical)) { _ in
            ifKeyWindow { flipCurrentImageVertical() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.vignetteImage)) { _ in
            ifKeyWindow { openVignetteHUD() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.adjustmentsImage)) { _ in
            ifKeyWindow { openAdjustmentsHUD() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.restoreFaces)) { _ in
            ifKeyWindow { restoreFacesOnCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeFaceRestoration)) { _ in
            ifKeyWindow { removeFaceRestoration() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.redEyeRemoval)) { _ in
            ifKeyWindow { applyRedEyeOnCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeRedEye)) { _ in
            ifKeyWindow { removeRedEyeCorrection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeBackground)) { _ in
            ifKeyWindow { removeBackgroundOnCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.restoreBackground)) { _ in
            ifKeyWindow { restoreBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeArtifacts)) { _ in
            ifKeyWindow { removeArtifactsOnCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.restoreArtifacts)) { _ in
            ifKeyWindow { restoreArtifacts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.upscaleImage2x)) { _ in
            ifKeyWindow { upscaleCurrentImage(scale: 2) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.upscaleImage4x)) { _ in
            ifKeyWindow { upscaleCurrentImage(scale: 4) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.removeUpscaling)) { _ in
            ifKeyWindow { removeUpscaling() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.saveEditedImage)) { _ in
            ifKeyWindow { saveEditedImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleSlideshow)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                toggleSlideshow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleThumbnails)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                showThumbnails.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleImageInfo)) { _ in
            ifKeyWindow { toggleInfoOverlay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.renameImage)) { _ in
            ifKeyWindow { renameCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.moveToTrash)) { _ in
            ifKeyWindow { moveCurrentImageToTrash() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyToFolder)) { _ in
            ifKeyWindow { copyCurrentImageToFolder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.moveToFolder)) { _ in
            ifKeyWindow { moveCurrentImageToFolder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyImage)) { _ in
            ifKeyWindow { copyImageToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyFilePath)) { _ in
            ifKeyWindow { copyFilePathToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.revealInFinder)) { _ in
            ifKeyWindow { revealCurrentImageInFinder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.openInPreview)) { _ in
            ifKeyWindow { openCurrentImageInDefaultApp() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.openWith)) { _ in
            ifKeyWindow { showOpenWithMenu() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleFavourite)) { _ in
            ifKeyWindow { toggleFavourite() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleFavouritesOnly)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                toggleShowFavouritesOnly()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.showKeyboardShortcuts)) { _ in
            showKeyboardShortcuts = true
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsView()
        }
        .onChange(of: slideshowInterval) { _, _ in
            if slideshow.isPlaying { slideshow.reschedule(interval: slideshowInterval) { [imageLoader] in imageLoader.nextImage() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                isFullScreen = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = true
                updateCursorVisibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = false
                showingOriginal = false
                updateCursorVisibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicOff)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                musicManager.setOff()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicChooseSong)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    showSongPicker = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicChoosePlaylist)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    showPlaylistPicker = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicShuffle)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    musicManager.setShuffle()
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(musicManager: musicManager) { song in
                musicManager.selectSong(song)
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerView(musicManager: musicManager) { playlist in
                musicManager.selectPlaylist(playlist)
            }
        }
        .alert("Music Access Required", isPresented: $musicManager.authorizationDenied) {
            Button("OK") {}
        } message: {
            Text("""
            Slidey needs access to your Music library to play background music. \
            You can grant access in System Settings > Privacy & Security > Media & Apple Music.
            """)
        }
        .alert("No Faces Detected", isPresented: $showNoFaceAlert) {
            Button("OK") {}
        } message: {
            Text("No faces were found in this image.")
        }
    }

    /// Run `action` only if this view's window is the key window AND no
    /// upscale is in progress. Edit-menu commands fan out to every open
    /// SlideshowView via NotificationCenter, so without the key-window gate
    /// a single keystroke would enhance/rotate/upscale every visible
    /// slideshow at once. The isProcessing gate prevents edits and
    /// navigation from racing an in-flight upscale on the same image.
    private func ifKeyWindow(_ action: () -> Void) {
        if (myWindow == nil || myWindow?.isKeyWindow == true) && !isProcessing {
            action()
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let key = keyPress.key

        if showDenoiseHUD {
            if key == .escape {
                cancelDenoise()
                return .handled
            }
            if keyPress.characters == "\r" {
                applyDenoise()
                return .handled
            }
            return .ignored
        }

        if showVignetteHUD {
            if key == .escape {
                cancelVignetteHUD()
                return .handled
            }
            if keyPress.characters == "\r" {
                applyVignetteToImage()
                return .handled
            }
            return .ignored
        }

        if showAdjustmentsHUD {
            if key == .escape {
                cancelAdjustmentsHUD()
                return .handled
            }
            if keyPress.characters == "\r" {
                applyAdjustmentsToImage()
                return .handled
            }
            return .ignored
        }

        if key == .escape {
            if isProcessing {
                cancelUpscale()
            } else {
                toggleFullScreen()
            }
            return .handled
        }

        // Lock the keyboard to Escape (handled above) while an upscale is in
        // flight, so the displayed image can't change underneath the
        // progress overlay.
        if isProcessing { return .handled }

        if key == .delete {
            moveCurrentImageToTrash()
            return .handled
        }

        if key == .home {
            DispatchQueue.main.async { imageLoader.jumpTo(index: 0) }
            return .handled
        }

        if key == .end {
            DispatchQueue.main.async { imageLoader.jumpTo(index: imageLoader.imageURLs.count - 1) }
            return .handled
        }

        // Defer all state mutations: SwiftUI processes .onKeyPress within its own
        // update pipeline, so synchronous @Published/@Observable writes here fire
        // "Publishing changes from within view updates" warnings.
        if zoomPan.zoomScale > 1.0 {
            switch key {
            case .leftArrow:
                if zoomPan.canPan(direction: .left, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    DispatchQueue.main.async { zoomPan.imageOffset.width += 50 }
                } else {
                    DispatchQueue.main.async { imageLoader.previousImage() }
                }
                return .handled
            case .rightArrow:
                if zoomPan.canPan(direction: .right, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    DispatchQueue.main.async { zoomPan.imageOffset.width -= 50 }
                } else {
                    DispatchQueue.main.async { imageLoader.nextImage() }
                }
                return .handled
            case .upArrow:
                if zoomPan.canPan(direction: .up, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    DispatchQueue.main.async { zoomPan.imageOffset.height += 50 }
                }
                return .handled
            case .downArrow:
                if zoomPan.canPan(direction: .down, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    DispatchQueue.main.async { zoomPan.imageOffset.height -= 50 }
                }
                return .handled
            default:
                break
            }
        } else {
            switch key {
            case .leftArrow:
                DispatchQueue.main.async { imageLoader.previousImage() }
                return .handled
            case .rightArrow:
                DispatchQueue.main.async { imageLoader.nextImage() }
                return .handled
            default:
                break
            }
        }

        return handleCharacterKeyPress(keyPress)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleCharacterKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.characters {
        case "+", "=":
            zoomPan.zoomScale = min(zoomPan.zoomScale * 1.2, 10.0)
            return .handled
        case "-", "_":
            zoomPan.zoomScale = max(zoomPan.zoomScale / 1.2, 0.1)
            if zoomPan.zoomScale <= 1.0 { zoomPan.reset() }
            return .handled
        case "s", "S":
            guard !keyPress.modifiers.contains(.command) else { return .ignored }
            zoomPan.zoomToNativeSize(image: effectiveDisplayImage, rotationAngle: rotationAngle)
            return .handled
        case "f", "F":
            zoomPan.zoomToFillScreen(image: effectiveDisplayImage, rotationAngle: rotationAngle)
            return .handled
        case "r":
            guard !keyPress.modifiers.contains(.command) else { return .ignored }
            rotateClockwise()
            return .handled
        case "R":
            rotateCounterClockwise()
            return .handled
        case "a":
            enhanceCurrentImage()
            return .handled
        case "A":
            removeEnhancement()
            return .handled
        case "m":
            smoothCurrentImage()
            return .handled
        case "M":
            removeSmoothing()
            return .handled
        case "h":
            sharpenCurrentImage()
            return .handled
        case "H":
            removeSharpening()
            return .handled
        case "q":
            openDenoiseHUD()
            return .handled
        case "u":
            guard !keyPress.modifiers.contains(.option) else { return .ignored }
            upscaleCurrentImage(scale: 2)
            return .handled
        case "U":
            removeUpscaling()
            return .handled
        case "i":
            toggleInfoOverlay()
            return .handled
        case "n":
            showFilename.toggle()
            return .handled
        case "d":
            showDebugWindow.toggle()
            return .handled
        case "t":
            showThumbnails.toggle()
            return .handled
        case "x":
            toggleFavourite()
            return .handled
        case "v":
            toggleShowFavouritesOnly()
            return .handled
        case "j":
            if !imageLoader.imageURLs.isEmpty {
                imageLoader.jumpTo(index: Int.random(in: 0..<imageLoader.imageURLs.count))
            }
            return .handled
        case "z":
            toggleSmartZoom()
            return .handled
        case "c":
            flipCurrentImageHorizontal()
            return .handled
        case "C":
            flipCurrentImageVertical()
            return .handled
        case "p":
            restoreFacesOnCurrentImage()
            return .handled
        case "P":
            removeFaceRestoration()
            return .handled
        case "g":
            applyRedEyeOnCurrentImage()
            return .handled
        case "G":
            removeRedEyeCorrection()
            return .handled
        case "k":
            removeBackgroundOnCurrentImage()
            return .handled
        case "K":
            restoreBackground()
            return .handled
        case "l":
            removeArtifactsOnCurrentImage()
            return .handled
        case "L":
            restoreArtifacts()
            return .handled
        case "e":
            openAdjustmentsHUD()
            return .handled
        case "b":
            showingOriginal = true
            return .handled
        case " ":
            toggleSlideshow()
            return .handled
        default:
            if zoomPan.zoomScale <= 1.0 {
                imageLoader.nextImage()
                return .handled
            }
        }
        return .ignored
    }

    private func captureWindow() {
        myWindow = NSApplication.shared.keyWindow
        if let myWindow {
            windowHasFocus = myWindow.isKeyWindow
            updateCursorVisibility()
        }
    }

    private func updateCursorVisibility() {
        let shouldHideCursor = !imageLoader.imageURLs.isEmpty && isFullScreen && windowHasFocus && !showThumbnails && slideshow.isPlaying
        let shouldAutoHideMenuBar = isFullScreen && slideshow.isPlaying

        DispatchQueue.main.async {
            if shouldHideCursor && !isCursorHidden {
                NSCursor.hide()
                isCursorHidden = true
            } else if !shouldHideCursor && isCursorHidden {
                NSCursor.unhide()
                isCursorHidden = false
                cursorShowTask?.cancel()
            }

            NSApplication.shared.presentationOptions = shouldAutoHideMenuBar ? [.autoHideMenuBar] : []
        }
    }

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            if self.isCursorHidden {
                NSCursor.unhide()
                self.isCursorHidden = false
                self.scheduleCursorHide()
            }
            return event
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if event.charactersIgnoringModifiers == "b" {
                DispatchQueue.main.async { self.showingOriginal = false }
            }
            return event
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        cursorShowTask?.cancel()
    }

    private func scheduleCursorHide() {
        cursorShowTask?.cancel()
        cursorShowTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            updateCursorVisibility()
        }
    }

    private func selectDirectory() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [
                .jpeg, .png, .heic, .gif, .bmp, .tiff, .webP
            ]

            if let window = self.myWindow ?? NSApplication.shared.keyWindow {
                panel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = panel.url {
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                        if isDir.boolValue {
                            self.openDirectory(url: url)
                        } else {
                            self.openDirectory(url: url.deletingLastPathComponent(), jumpTo: url)
                        }
                    }
                }
            }
        }
    }

    private func openRecent(_ entry: RecentDirectory) {
        guard let url = recentDirectories.resolveAndBeginAccess(for: entry) else {
            return
        }
        openDirectory(url: url, isScoped: true)
    }

    private func openDirectory(url: URL, isScoped: Bool = false, jumpTo targetURL: URL? = nil) {
        // Release any prior security-scoped access before switching.
        if let prior = scopedDirectory {
            prior.stopAccessingSecurityScopedResource()
        }
        scopedDirectory = isScoped ? url : nil

        selectedDirectory = url
        recentDirectories.addDirectory(url)

        // Reset ephemeral image modifications (rotation persists per URL)
        rotationAngle = .zero
        enhancedImages = [:]
        smoothedImages = [:]
        sharpenedImages = [:]
        upscaledImages = [:]
        upscaleFactors = [:]
        savedZoomScales = [:]
        savedPanOffsets = [:]
        infoOverlayURLs = []
        imageInfoCache = [:]
        zoomPan.reset()

        imageLoader.loadImagesFromDirectory(url: url, jumpTo: targetURL)
        windowTitle = "Slidey"
        // updateDisplayImage will be called by onChange(of: imageLoader.imageURLs)
    }

    private func toggleSlideshow() {
        slideshow.toggle(
            isProcessing: isProcessing,
            imageCount: imageLoader.imageURLs.count,
            interval: slideshowInterval,
            advance: { [imageLoader] in imageLoader.nextImage() },
            shouldStop: { [imageLoader] in
                let loopEnabled = UserDefaults.standard.object(forKey: "slideshowLoop") as? Bool ?? true
                return !loopEnabled && imageLoader.currentIndex >= imageLoader.imageURLs.count - 1
            },
            onStart: autoPlayMusic ? { [musicManager] in musicManager.resumeIfConfigured() } : nil
        )
    }

    /// Consumes a URL from `pendingOpens` (set by AppDelegate when Launch
    /// Services hands us a folder via dock-drop, "Open With…", or `open -a`).
    /// Only the key window claims the URL, so multi-window apps don't open
    /// the same folder several times. Skipped while an upscale is in flight;
    /// re-attempted when isProcessing flips back to false.
    private func consumePendingOpenIfPossible() {
        guard let url = pendingOpens.pending else { return }
        guard !isProcessing else { return }
        guard myWindow == nil || myWindow?.isKeyWindow == true else { return }
        pendingOpens.pending = nil
        openDirectory(url: url, isScoped: false)
    }

    private func scheduleAutoOpenRecent() {
        guard autoOpenRecent,
              imageLoader.imageURLs.isEmpty,
              pendingOpens.pending == nil,
              recentDirectories.directories.first != nil else { return }

        isAutoOpening = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.imageLoader.imageURLs.isEmpty,
                  self.pendingOpens.pending == nil,
                  let first = self.recentDirectories.directories.first else {
                self.isAutoOpening = false
                return
            }
            self.openRecent(first)
            // loadImagesFromDirectory dispatches its final update to main.async,
            // so enqueue after it to catch the case where the directory had no images
            // or the bookmark couldn't be resolved.
            DispatchQueue.main.async {
                self.slideshow.stop()
                if self.imageLoader.imageURLs.isEmpty {
                    self.isAutoOpening = false
                }
            }
        }
    }

    /// Drop handler. Accepts the first file URL that resolves to a directory
    /// and opens it. Plain files and drops mid-upscale are ignored.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isProcessing else { return false }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else {
                return
            }
            DispatchQueue.main.async {
                openDirectory(url: url, isScoped: false)
            }
        }
        return true
    }

    private func enterFullScreen() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.keyWindow {
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                    isFullScreen = true
                }
            }
        }
    }

    private func currentURLRotation() -> Angle {
        guard let url = imageLoader.currentImageURL else { return .zero }
        return rotationAngles[url] ?? .zero
    }

    private func rotateClockwise() {
        rotationAngle = Angle(degrees: rotationAngle.degrees + 90)
        if let url = imageLoader.currentImageURL {
            rotationAngles[url] = rotationAngle
            saveFavourites()
        }
    }

    private func rotateCounterClockwise() {
        rotationAngle = Angle(degrees: rotationAngle.degrees - 90)
        if let url = imageLoader.currentImageURL {
            rotationAngles[url] = rotationAngle
            saveFavourites()
        }
    }

    private func toggleFullScreen() {
        if let window = NSApplication.shared.keyWindow {
            window.toggleFullScreen(nil)
            isFullScreen.toggle()
            updateCursorVisibility()
        }
    }

    private func acquireDisplaySleepAssertion() {
        guard !hasDisplaySleepAssertion else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Slidey fullscreen slideshow" as CFString,
            &displaySleepAssertionID
        )
        if result == kIOReturnSuccess {
            hasDisplaySleepAssertion = true
        }
    }

    private func releaseDisplaySleepAssertion() {
        guard hasDisplaySleepAssertion else { return }
        IOPMAssertionRelease(displaySleepAssertionID)
        hasDisplaySleepAssertion = false
    }

    private func exitFullScreen() {
        if let window = NSApplication.shared.keyWindow {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                isFullScreen = false
                updateCursorVisibility()
            }
        }
    }

    private func updateWindowTitle(_ title: String) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.keyWindow {
                window.title = title
            }
        }
    }

    static func imageDimensions(for url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    static func titleForImage(at url: URL) -> String {
        let name = url.lastPathComponent
        guard let dims = imageDimensions(for: url) else { return name }
        return "\(name) (\(dims.width)×\(dims.height))"
    }

    // MARK: - onChange helpers (called via DispatchQueue.main.async to avoid publishing during view update)

    private func onImageURLsEmptyChanged(_ isEmpty: Bool) {
        if !isEmpty {
            isAutoOpening = false
            rotationAngle = currentURLRotation()
            updateDisplayImage()
            enterFullScreen()
            if let url = imageLoader.currentImageURL {
                windowTitle = Self.titleForImage(at: url)
            }
        } else {
            slideshow.stop()
            musicManager.deactivate()
        }
        updateCursorVisibility()
    }

    private func onImageURLsChanged(_ newURLs: [URL]) {
        let valid = imageLoader.allImageURLs.isEmpty ? Set(newURLs) : Set(imageLoader.allImageURLs)
        rotationAngles = rotationAngles.filter { valid.contains($0.key) }
        enhancedImages = enhancedImages.filter { valid.contains($0.key) }
        smoothedImages = smoothedImages.filter { valid.contains($0.key) }
        sharpenedImages = sharpenedImages.filter { valid.contains($0.key) }
        upscaledImages = upscaledImages.filter { valid.contains($0.key) }
        upscaleFactors = upscaleFactors.filter { valid.contains($0.key) }
        savedZoomScales = savedZoomScales.filter { valid.contains($0.key) }
        savedPanOffsets = savedPanOffsets.filter { valid.contains($0.key) }
        infoOverlayURLs = infoOverlayURLs.intersection(valid)
        imageInfoCache = imageInfoCache.filter { valid.contains($0.key) }
        rotationAngle = currentURLRotation()
        if !newURLs.isEmpty { updateDisplayImage() }
    }

    private func onCurrentIndexChanged() {
        let newURL = imageLoader.currentImageURL
        if newURL != lastDisplayedURL {
            if let departingURL = lastDisplayedURL {
                savedZoomScales[departingURL] = zoomPan.zoomScale
                savedPanOffsets[departingURL] = zoomPan.imageOffset
            }
            if let newURL, let savedZoom = savedZoomScales[newURL] {
                zoomPan.zoomScale = savedZoom
                zoomPan.imageOffset = savedPanOffsets[newURL] ?? .zero
            } else {
                zoomPan.reset()
            }
            lastDisplayedURL = newURL
            if let newURL { windowTitle = Self.titleForImage(at: newURL) }
        }
        rotationAngle = currentURLRotation()
        updateDisplayImage()
        if smartZoomEnabled, let url = imageLoader.currentImageURL, let image = imageLoader.currentImage {
            applySmartZoomIfNeeded(for: url, image: image)
        }
        // Reset the auto-advance clock on every navigation so the next tick is always `interval` from now.
        if slideshow.isPlaying { slideshow.reschedule(interval: slideshowInterval) { [imageLoader] in imageLoader.nextImage() } }
    }

    private func updateDisplayImage() {
        guard let url = imageLoader.currentImageURL else {
            currentDisplayImage = imageLoader.currentImage
            return
        }
        // Priority: bgRemoved > faceRestored > redEye > artifactRemoved > upscaled > sharpened > smoothed > enhanced > original
        var baseImage: NSImage?
        if let bgRemoved = backgroundRemovedImages[url] {
            baseImage = bgRemoved
            windowTitle = Self.titleForImage(at: url) + " [background removed]"
        } else if let faceRestored = faceRestoredImages[url] {
            baseImage = faceRestored
            windowTitle = Self.titleForImage(at: url) + " [faces restored]"
        } else if let redEye = redEyedImages[url] {
            baseImage = redEye
            windowTitle = Self.titleForImage(at: url) + " [red-eye removed]"
        } else if let artifactRemoved = artifactRemovedImages[url] {
            baseImage = artifactRemoved
            windowTitle = Self.titleForImage(at: url) + " [artifacts removed]"
        } else if let upscaled = upscaledImages[url] {
            baseImage = upscaled
            let factor = upscaleFactors[url] ?? 4
            windowTitle = Self.titleForImage(at: url) + " [\(factor)\u{00d7} upscaled]"
        } else {
            if let sharpened = sharpenedImages[url] { baseImage = sharpened }
            else if let smoothed = smoothedImages[url] { baseImage = smoothed }
            else if let enhanced = enhancedImages[url] { baseImage = enhanced }
            else { baseImage = imageLoader.currentImage }
            windowTitle = Self.titleForImage(at: url)
        }
        // Apply flip and photo effect as the final compositing steps
        let isFlippedH = flippedHorizontally.contains(url.absoluteString)
        let isFlippedV = flippedVertically.contains(url.absoluteString)
        let needsFlip = isFlippedH || isFlippedV
        if let effectName = imageEffects[url] {
            if let cached = effectImages[url] {
                currentDisplayImage = cached
            } else if let base = baseImage {
                let processedBase = needsFlip
                    ? (applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: base) ?? base)
                    : base
                let effected = applyPhotoEffect(effectName, to: processedBase)
                effectImages[url] = effected ?? processedBase
                currentDisplayImage = effectImages[url]
            }
        } else if needsFlip, let base = baseImage {
            currentDisplayImage = applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: base) ?? base
        } else {
            currentDisplayImage = baseImage
        }
        // Apply adjustments (skip during HUD preview)
        if !showAdjustmentsHUD, let adj = adjustmentURLLevels[url.absoluteString], !adj.isIdentity,
           let image = currentDisplayImage {
            currentDisplayImage = applyAdjustments(adj, to: image) ?? image
        }
        // Apply vignette as the absolute final step (skip during HUD preview)
        if !showVignetteHUD, let vigLevel = vignetteURLLevels[url.absoluteString], vigLevel > 0,
           let image = currentDisplayImage {
            currentDisplayImage = applyVignette(intensity: vigLevel, to: image) ?? image
        }
        // Update menu display to reflect active effect for this image
        UserDefaults.standard.set(imageEffects[url] ?? "", forKey: "activePhotoEffect")
        // Re-apply persisted edits for images not yet processed in this session
        let needsEnhance = enhancedURLStrings.contains(url.absoluteString) && enhancedImages[url] == nil
        let needsSmooth = smoothedURLStrings.contains(url.absoluteString) && smoothedImages[url] == nil
        let needsSharpen = sharpenedURLStrings.contains(url.absoluteString) && sharpenedImages[url] == nil
        if needsEnhance || needsSmooth || needsSharpen {
            DispatchQueue.main.async { [url] in
                guard self.imageLoader.currentImageURL == url else { return }
                if needsEnhance { self.enhanceCurrentImage() }
                if needsSmooth {
                    let level = self.denoiseURLLevels[url.absoluteString].map { $0 / 1000.0 } ?? 0.02
                    self.smoothCurrentImage(noiseLevel: level)
                }
                if needsSharpen { self.sharpenCurrentImage() }
            }
        }
    }

    private func enhanceCurrentImage() {
        guard let originalImage = imageLoader.currentImage,
              let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filters = ciImage.autoAdjustmentFilters()

        var outputImage = ciImage
        for filter in filters {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            if let result = filter.outputImage {
                outputImage = result
            }
        }

        let context = CIContext()
        if let enhancedCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let enhancedNSImage = NSImage(cgImage: enhancedCGImage, size: originalImage.size)
            guard let url = imageLoader.currentImageURL else { return }
            enhancedImages[url] = enhancedNSImage
            enhancedURLStrings.insert(url.absoluteString)
            saveFavourites()
            invalidateUpscaling(for: url)
            setDisplay(base: enhancedNSImage, for: url)
        }
    }

    private func removeEnhancement() {
        guard let url = imageLoader.currentImageURL else { return }
        enhancedImages[url] = nil
        enhancedURLStrings.remove(url.absoluteString)
        saveFavourites()
        invalidateUpscaling(for: url)
        updateDisplayImage()
    }

    private func smoothCurrentImage(noiseLevel: Double = 0.02) {
        guard let originalImage = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CINoiseReduction") else { return }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(noiseLevel, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: "inputSharpness")

        guard let outputImage = filter.outputImage else { return }

        let context = CIContext()
        if let smoothedCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let smoothedNSImage = NSImage(cgImage: smoothedCGImage, size: originalImage.size)
            guard let url = imageLoader.currentImageURL else { return }
            smoothedImages[url] = smoothedNSImage
            smoothedURLStrings.insert(url.absoluteString)
            saveFavourites()
            invalidateUpscaling(for: url)
            setDisplay(base: smoothedNSImage, for: url)
        }
    }

    private func removeSmoothing() {
        guard let url = imageLoader.currentImageURL else { return }
        smoothedImages[url] = nil
        smoothedURLStrings.remove(url.absoluteString)
        saveFavourites()
        invalidateUpscaling(for: url)
        updateDisplayImage()
    }

    private func sharpenCurrentImage() {
        guard let originalImage = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.4, forKey: "inputSharpness")

        guard let outputImage = filter.outputImage else { return }

        let context = CIContext()
        if let sharpenedCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let sharpenedNSImage = NSImage(cgImage: sharpenedCGImage, size: originalImage.size)
            guard let url = imageLoader.currentImageURL else { return }
            sharpenedImages[url] = sharpenedNSImage
            sharpenedURLStrings.insert(url.absoluteString)
            saveFavourites()
            invalidateUpscaling(for: url)
            setDisplay(base: sharpenedNSImage, for: url)
        }
    }

    private func removeSharpening() {
        guard let url = imageLoader.currentImageURL else { return }
        sharpenedImages[url] = nil
        sharpenedURLStrings.remove(url.absoluteString)
        saveFavourites()
        invalidateUpscaling(for: url)
        updateDisplayImage()
    }

    private func applyPhotoEffect(_ filterName: String, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let outputImage = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let cgOut = ctx.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    private func setDisplay(base: NSImage, for url: URL) {
        let isFlippedH = flippedHorizontally.contains(url.absoluteString)
        let isFlippedV = flippedVertically.contains(url.absoluteString)
        let flippedBase = (isFlippedH || isFlippedV)
            ? (applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: base) ?? base)
            : base
        effectImages[url] = nil
        if let name = imageEffects[url], let result = applyPhotoEffect(name, to: flippedBase) {
            effectImages[url] = result
            currentDisplayImage = result
        } else {
            currentDisplayImage = flippedBase
        }
        // Adjustments (skip during HUD preview)
        if !showAdjustmentsHUD, let adj = adjustmentURLLevels[url.absoluteString], !adj.isIdentity,
           let image = currentDisplayImage {
            currentDisplayImage = applyAdjustments(adj, to: image) ?? image
        }
        // Vignette as final step (skip during HUD preview)
        if !showVignetteHUD, let vigLevel = vignetteURLLevels[url.absoluteString], vigLevel > 0,
           let image = currentDisplayImage {
            currentDisplayImage = applyVignette(intensity: vigLevel, to: image) ?? image
        }
    }

    private func applyFlipTransform(horizontal: Bool, vertical: Bool, to image: NSImage) -> NSImage? {
        guard horizontal || vertical else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var ciImage = CIImage(cgImage: cgImage)
        if horizontal {
            let t = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -ciImage.extent.width, y: 0)
            ciImage = ciImage.transformed(by: t)
        }
        if vertical {
            let t = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height)
            ciImage = ciImage.transformed(by: t)
        }
        let context = CIContext()
        guard let cgOut = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    private func flipCurrentImageHorizontal() {
        guard let url = imageLoader.currentImageURL else { return }
        let key = url.absoluteString
        if flippedHorizontally.contains(key) { flippedHorizontally.remove(key) } else { flippedHorizontally.insert(key) }
        effectImages[url] = nil
        saveFavourites()
        updateDisplayImage()
    }

    private func flipCurrentImageVertical() {
        guard let url = imageLoader.currentImageURL else { return }
        let key = url.absoluteString
        if flippedVertically.contains(key) { flippedVertically.remove(key) } else { flippedVertically.insert(key) }
        effectImages[url] = nil
        saveFavourites()
        updateDisplayImage()
    }

    private func setPhotoEffect(_ filterName: String?) {
        guard let url = imageLoader.currentImageURL else { return }
        let name = filterName.flatMap { $0.isEmpty ? nil : $0 }
        guard imageEffects[url] != name else { return }
        imageEffects[url] = name
        effectImages[url] = nil
        saveFavourites()
        UserDefaults.standard.set(name ?? "", forKey: "activePhotoEffect")
        updateDisplayImage()
    }

    private func applyVignette(intensity: Double, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIVignetteEffect") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: "inputCenter")
        filter.setValue(max(ciImage.extent.width, ciImage.extent.height) * 0.75, forKey: "inputRadius")
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        guard let outputImage = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgOut = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    private func openVignetteHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying else { return }
        vignetteIntensity = vignetteURLLevels[url.absoluteString] ?? 1.0
        showVignetteHUD = true         // pipeline now skips vignette
        updateDisplayImage()            // recomputes without vignette → clean base
        vignetteBaseImage = currentDisplayImage
        scheduleVignettePreview()
    }

    private func scheduleVignettePreview() {
        vignetteTask?.cancel()
        vignetteTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyVignettePreview() }
        }
    }

    private func applyVignettePreview() {
        guard let base = vignetteBaseImage else { return }
        currentDisplayImage = (vignetteIntensity > 0 ? applyVignette(intensity: vignetteIntensity, to: base) : nil) ?? base
    }

    private func applyVignetteToImage() {
        guard let url = imageLoader.currentImageURL else { cancelVignetteHUD(); return }
        if vignetteIntensity > 0 {
            vignetteURLLevels[url.absoluteString] = vignetteIntensity
        } else {
            vignetteURLLevels.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showVignetteHUD = false
        vignetteTask?.cancel()
        vignetteTask = nil
        vignetteBaseImage = nil
        updateDisplayImage()
    }

    private func cancelVignetteHUD() {
        guard showVignetteHUD else { return }
        showVignetteHUD = false
        vignetteTask?.cancel()
        vignetteTask = nil
        vignetteBaseImage = nil
        updateDisplayImage()  // restores pipeline including any previously persisted vignette
    }

    private func applyAdjustments(_ adj: ImageAdjustments, to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var ciImage = CIImage(cgImage: cgImage)
        if adj.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adj.exposure, forKey: kCIInputEVKey)
            ciImage = f.outputImage ?? ciImage
        }
        if adj.highlights != 0 || adj.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(Float(1 - adj.highlights), forKey: "inputHighlightAmount")
            f.setValue(Float(adj.shadows + 0.5), forKey: "inputShadowAmount")
            ciImage = f.outputImage ?? ciImage
        }
        if adj.vibrance != 0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adj.vibrance, forKey: "inputAmount")
            ciImage = f.outputImage ?? ciImage
        }
        if adj.warmth != 0, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            let neutral = CIVector(x: 6500 + adj.warmth * 2000, y: 0)
            f.setValue(neutral, forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            ciImage = f.outputImage ?? ciImage
        }
        let ctx = CIContext()
        guard let cgOut = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: image.size)
    }

    private func openAdjustmentsHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying else { return }
        adjustments = adjustmentURLLevels[url.absoluteString] ?? .init()
        showAdjustmentsHUD = true
        updateDisplayImage()
        adjustmentsBaseImage = currentDisplayImage
        scheduleAdjustmentsPreview()
    }

    private func scheduleAdjustmentsPreview() {
        adjustmentsTask?.cancel()
        adjustmentsTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyAdjustmentsPreview() }
        }
    }

    private func applyAdjustmentsPreview() {
        guard let base = adjustmentsBaseImage else { return }
        currentDisplayImage = (adjustments.isIdentity ? nil : applyAdjustments(adjustments, to: base)) ?? base
    }

    private func applyAdjustmentsToImage() {
        guard let url = imageLoader.currentImageURL else { cancelAdjustmentsHUD(); return }
        if !adjustments.isIdentity {
            adjustmentURLLevels[url.absoluteString] = adjustments
        } else {
            adjustmentURLLevels.removeValue(forKey: url.absoluteString)
        }
        saveFavourites()
        showAdjustmentsHUD = false
        adjustmentsTask?.cancel(); adjustmentsTask = nil; adjustmentsBaseImage = nil
        updateDisplayImage()
    }

    private func cancelAdjustmentsHUD() {
        guard showAdjustmentsHUD else { return }
        showAdjustmentsHUD = false
        adjustmentsTask?.cancel(); adjustmentsTask = nil; adjustmentsBaseImage = nil
        updateDisplayImage()
    }

    private func toggleSmartZoom() {
        smartZoomEnabled.toggle()
        if smartZoomEnabled {
            guard let url = imageLoader.currentImageURL,
                  let image = imageLoader.currentImage else { return }
            applySmartZoomIfNeeded(for: url, image: image)
        } else {
            zoomPan.reset()
        }
    }

    private func applySmartZoomIfNeeded(for url: URL, image: NSImage) {
        if let cached = saliencyRects[url] {
            zoomPan.zoomToSalientRegion(cached, image: image, rotationAngle: rotationAngle)
        } else {
            computeSaliency(for: url, image: image)
        }
    }

    private func computeSaliency(for url: URL, image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [url] in
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) } catch { return }
            guard let results = request.results as? [VNSaliencyImageObservation],
                  let observation = results.first else { return }
            var unionRect = CGRect.null
            for obj in observation.salientObjects ?? [] {
                unionRect = unionRect.union(obj.boundingBox)
            }
            guard !unionRect.isNull else { return }
            DispatchQueue.main.async { [url] in
                self.saliencyRects[url] = unionRect
                guard self.smartZoomEnabled, self.imageLoader.currentImageURL == url else { return }
                self.zoomPan.zoomToSalientRegion(unionRect, image: image, rotationAngle: self.rotationAngle)
            }
        }
    }

    private func openDenoiseHUD() {
        guard let url = imageLoader.currentImageURL, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying else { return }
        // Start from the enhanced (or original) image, not the currently smoothed/sharpened one,
        // so the HUD adjusts denoise from the correct base.
        denoiseBaseImage = enhancedImages[url] ?? imageLoader.currentImage
        denoiseLevel = denoiseURLLevels[url.absoluteString] ?? 50.0
        showDenoiseHUD = true
        applyDenoisePreview()
    }

    private func scheduleDenoisePreview() {
        denoiseTask?.cancel()
        denoiseTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await MainActor.run { applyDenoisePreview() }
        }
    }

    private func applyDenoisePreview() {
        guard let base = denoiseBaseImage,
              let cgImage = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let noiseLevel = denoiseLevel / 1000.0
        guard noiseLevel > 0 else { currentDisplayImage = base; return }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CINoiseReduction") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(noiseLevel, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: "inputSharpness")
        guard let outputImage = filter.outputImage else { return }
        let context = CIContext()
        if let cgOut = context.createCGImage(outputImage, from: outputImage.extent) {
            currentDisplayImage = NSImage(cgImage: cgOut, size: base.size)
        }
    }

    private func applyDenoise() {
        guard let url = imageLoader.currentImageURL,
              let result = currentDisplayImage else { cancelDenoise(); return }
        // currentDisplayImage is the raw denoise preview (denoiseBaseImage has no photo effect applied)
        smoothedImages[url] = result
        smoothedURLStrings.insert(url.absoluteString)
        denoiseURLLevels[url.absoluteString] = denoiseLevel
        saveFavourites()
        invalidateUpscaling(for: url)  // also clears effectImages[url]
        showDenoiseHUD = false
        denoiseTask?.cancel()
        denoiseTask = nil
        denoiseBaseImage = nil
        updateDisplayImage()  // reapplies photo effect over the new smooth base
    }

    private func cancelDenoise() {
        guard showDenoiseHUD else { return }
        showDenoiseHUD = false
        denoiseTask?.cancel()
        denoiseTask = nil
        denoiseBaseImage = nil
        updateDisplayImage()  // restores pre-HUD display including any active photo effect
    }

    private func upscaleCurrentImage(scale: Int) {
        guard !isProcessing else { return }
        guard let targetURL = imageLoader.currentImageURL else { return }
        // Upscale the best non-upscaled version: smoothed > enhanced > original
        guard let sourceImage = sharpenedImages[targetURL] ?? smoothedImages[targetURL] ?? enhancedImages[targetURL] ?? imageLoader.currentImage else { return }

        isProcessing = true
        upscaleCancelled = false
        upscaleProgress = 0
        activeUpscaleScale = scale
        debugOutput = "Starting \(scale)x Core ML upscale...\n"

        let modelName = scale == 2 ? "RealESRGAN_x2plus_522_fp16" : "RealESRGAN_x4plus_522_fp16"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Xcode compiles .mlpackage → .mlmodelc at build time; fall back to
                // .mlpackage for any non-Xcode distribution path.
                guard let pkgURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                                    Bundle.main.url(forResource: modelName, withExtension: "mlpackage",
                                                    subdirectory: "Resources") ??
                                    Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: \(modelName) not found in bundle\n"
                        self.isProcessing = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.debugOutput += "Loading model (may take ~30s on first run)...\n"
                }

                let config = MLModelConfiguration()
                config.computeUnits = .all
                let model = try MLModel(contentsOf: pkgURL, configuration: config)
                let outputKey = model.modelDescription.outputDescriptionsByName.keys.first!

                guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Could not get CGImage from source image\n"
                        self.isProcessing = false
                    }
                    return
                }

                let imgW = cgImage.width
                let imgH = cgImage.height
                let outW = imgW * scale
                let outH = imgH * scale

                DispatchQueue.main.async {
                    self.debugOutput += "Image: \(imgW)×\(imgH) → \(outW)×\(outH)\n"
                    self.debugOutput += "Upscaling via Core ML...\n"
                }

                // Render source image to a flat RGBA UInt8 pixel buffer
                var inputPixels = [UInt8](repeating: 0, count: imgW * imgH * 4)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let drawCtx = CGContext(
                    data: &inputPixels, width: imgW, height: imgH,
                    bitsPerComponent: 8, bytesPerRow: imgW * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Failed to create drawing context\n"
                        self.isProcessing = false
                    }
                    return
                }
                drawCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

                if self.upscaleCancelled {
                    DispatchQueue.main.async { self.isProcessing = false }
                    return
                }

                // Run tiled Core ML inference
                var outputPixels = [UInt8](repeating: 255, count: outW * outH * 4)
                try Self.runTiledUpscale(
                    model: model, outputKey: outputKey,
                    inputPixels: inputPixels, imgW: imgW, imgH: imgH,
                    outputPixels: &outputPixels, outW: outW, outH: outH,
                    scale: scale,
                    isCancelled: { self.upscaleCancelled },
                    onProgress: { p in DispatchQueue.main.async { self.upscaleProgress = p } }
                )

                if self.upscaleCancelled {
                    DispatchQueue.main.async {
                        self.debugOutput += "Upscaling cancelled.\n"
                        self.isProcessing = false
                    }
                    return
                }

                // Wrap output pixel buffer in NSImage
                guard let outCtx = CGContext(
                    data: &outputPixels, width: outW, height: outH,
                    bitsPerComponent: 8, bytesPerRow: outW * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ), let outCGImage = outCtx.makeImage() else {
                    DispatchQueue.main.async {
                        self.debugOutput += "ERROR: Failed to create output image\n"
                        self.isProcessing = false
                    }
                    return
                }

                let result = NSImage(cgImage: outCGImage, size: NSSize(width: outW, height: outH))
                DispatchQueue.main.async {
                    self.upscaledImages[targetURL] = result
                    self.upscaleFactors[targetURL] = scale
                    self.effectImages[targetURL] = nil
                    self.upscaleProgress = 1.0
                    self.debugOutput += "SUCCESS: \(imgW)×\(imgH) → \(outW)×\(outH)\n"
                    self.isProcessing = false
                    self.updateDisplayImage()
                }
            } catch {
                DispatchQueue.main.async {
                    self.debugOutput += "ERROR: \(error.localizedDescription)\n"
                    self.isProcessing = false
                }
            }
        }
    }

    // Runs Real-ESRGAN inference on tiled regions of the input and accumulates
    // results with linear-ramp blending in overlap zones to avoid seams.
    // Tile parameters match the hanxiao/real-esrgan-coreml reference implementation:
    // 512px tiles, 32px overlap, 10px reflect pre-pad, 522×522 model input.
    // swiftlint:disable:next function_parameter_count
    private static func runTiledUpscale(
        model: MLModel, outputKey: String,
        inputPixels: [UInt8], imgW: Int, imgH: Int,
        outputPixels: inout [UInt8], outW: Int, outH: Int,
        scale: Int,
        isCancelled: () -> Bool,
        onProgress: (Double) -> Void
    ) throws {
        let tileSize = 512
        let tileOverlap = 32
        let prePad = 10
        let modelSize = tileSize + prePad  // 522
        let outModelSide = modelSize * scale

        // Float accumulators for weighted blending
        var accR = [Float](repeating: 0, count: outW * outH)
        var accG = [Float](repeating: 0, count: outW * outH)
        var accB = [Float](repeating: 0, count: outW * outH)
        var accW = [Float](repeating: 0, count: outW * outH)

        func tileStarts(total: Int) -> [Int] {
            guard total > tileSize else { return [0] }
            var positions: [Int] = []
            let stride = tileSize - tileOverlap
            var pos = 0
            while pos < total {
                if pos + tileSize >= total {
                    positions.append(max(0, total - tileSize))
                    break
                }
                positions.append(pos)
                pos += stride
            }
            return positions
        }

        let yStarts = tileStarts(total: imgH)
        let xStarts = tileStarts(total: imgW)
        let totalTiles = yStarts.count * xStarts.count
        var tilesDone = 0

        // Reuse a single MLMultiArray across tiles to avoid per-tile allocation
        let inputArray = try MLMultiArray(
            shape: [1, 3, NSNumber(value: modelSize), NSNumber(value: modelSize)],
            dataType: .float32
        )
        let inPtr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 3 * modelSize * modelSize)

        for y0 in yStarts {
            if isCancelled() { return }
            for x0 in xStarts {
                if isCancelled() { return }

                let y1 = min(y0 + tileSize, imgH)
                let x1 = min(x0 + tileSize, imgW)
                let tileH = y1 - y0
                let tileW = x1 - x0
                let paddedH = tileH + prePad
                let paddedW = tileW + prePad

                // Fill model input (NCHW, float32 [0,1]) with reflect-padded tile data.
                // Two-layer reflect: square-pad (modelSize → paddedH×paddedW) then
                // pre-pad (paddedH → tileH). Uses periodic reflect-clamp so multiple
                // bounces are handled correctly when the tile is smaller than prePad or
                // when the square-pad zone is large relative to paddedH.
                func ri(_ i: Int, _ n: Int) -> Int {
                    guard n > 1 else { return 0 }
                    let p = 2 * (n - 1)
                    let j = ((i % p) + p) % p
                    return j < n ? j : p - j
                }
                for row in 0..<modelSize {
                    for col in 0..<modelSize {
                        let tr = ri(ri(row, paddedH), tileH)
                        let tc = ri(ri(col, paddedW), tileW)
                        let pixIdx = ((y0 + tr) * imgW + (x0 + tc)) * 4
                        let pos = row * modelSize + col
                        inPtr[0 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx])     / 255.0
                        inPtr[1 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx + 1]) / 255.0
                        inPtr[2 * modelSize * modelSize + pos] = Float(inputPixels[pixIdx + 2]) / 255.0
                    }
                }

                let inFeatures = try MLDictionaryFeatureProvider(
                    dictionary: ["input": MLFeatureValue(multiArray: inputArray)]
                )
                let outFeatures = try model.prediction(from: inFeatures)
                guard let outArray = outFeatures.featureValue(for: outputKey)?.multiArrayValue else {
                    throw NSError(domain: "SlideyUpscale", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Model produced no output"])
                }

                // Read output using raw pointer + actual strides to handle fp16/fp32
                // regardless of how Core ML arranges memory. MLShapedArray<Float> crashes
                // when the underlying array is Float16 (type mismatch is a fatal error).
                let outRank = outArray.shape.count
                let outStrides = outArray.strides
                // For [1,C,H,W] outRank=4 → chanSt=strides[1]; for [C,H,W] → strides[0]
                let chanSt = outStrides[outRank - 3].intValue
                let rowSt  = outStrides[outRank - 2].intValue
                let colSt  = outStrides[outRank - 1].intValue

                // Accumulate tile output with linear-ramp blend weights in overlap zones
                let rampPx = tileOverlap * scale

                // Hoist the data-type branch outside the pixel loop
                let isFP16 = outArray.dataType == .float16
                let rawPtr16 = isFP16 ? outArray.dataPointer.bindMemory(
                    to: UInt16.self, capacity: outArray.count) : nil
                let rawPtr32 = isFP16 ? nil : outArray.dataPointer.bindMemory(
                    to: Float.self, capacity: outArray.count)

                for ty in 0..<tileH * scale {
                    let gy = y0 * scale + ty
                    for tx in 0..<tileW * scale {
                        let gx = x0 * scale + tx
                        var w: Float = 1.0
                        if rampPx > 0 {
                            if y0 > 0 && ty < rampPx            { w *= Float(ty) / Float(rampPx) }
                            if y1 < imgH && ty >= tileH * scale - rampPx { w *= Float(tileH * scale - 1 - ty) / Float(rampPx) }
                            if x0 > 0 && tx < rampPx            { w *= Float(tx) / Float(rampPx) }
                            if x1 < imgW && tx >= tileW * scale - rampPx { w *= Float(tileW * scale - 1 - tx) / Float(rampPx) }
                        }
                        let idx = gy * outW + gx
                        let base = ty * rowSt + tx * colSt
                        let r0: Float, g0: Float, b0: Float
                        if isFP16, let ptr = rawPtr16 {
                            r0 = Float(Float16(bitPattern: ptr[base]))
                            g0 = Float(Float16(bitPattern: ptr[chanSt + base]))
                            b0 = Float(Float16(bitPattern: ptr[2 * chanSt + base]))
                        } else if let ptr = rawPtr32 {
                            r0 = ptr[base]
                            g0 = ptr[chanSt + base]
                            b0 = ptr[2 * chanSt + base]
                        } else {
                            (r0, g0, b0) = (0, 0, 0)
                        }
                        accR[idx] += r0 * w
                        accG[idx] += g0 * w
                        accB[idx] += b0 * w
                        accW[idx] += w
                    }
                }

                tilesDone += 1
                onProgress(Double(tilesDone) / Double(totalTiles))
            }
        }

        if isCancelled() { return }

        // Normalise and write to UInt8 output
        for i in 0..<outW * outH {
            let w = max(accW[i], 1e-8)
            outputPixels[i * 4]     = UInt8(min(255, max(0, Int((accR[i] / w * 255).rounded()))))
            outputPixels[i * 4 + 1] = UInt8(min(255, max(0, Int((accG[i] / w * 255).rounded()))))
            outputPixels[i * 4 + 2] = UInt8(min(255, max(0, Int((accB[i] / w * 255).rounded()))))
        }
    }

    private func cancelUpscale() {
        upscaleCancelled = true
    }

    private func invalidateUpscaling(for url: URL) {
        upscaledImages[url] = nil
        upscaleFactors[url] = nil
        effectImages[url] = nil
    }

    private func removeUpscaling() {
        guard let url = imageLoader.currentImageURL else { return }
        upscaledImages[url] = nil
        upscaleFactors[url] = nil
        updateDisplayImage()
    }

    private func removeFaceRestoration() {
        guard let url = imageLoader.currentImageURL else { return }
        faceRestoredImages[url] = nil
        updateDisplayImage()
    }

    private func removeRedEyeCorrection() {
        guard let url = imageLoader.currentImageURL else { return }
        redEyedImages[url] = nil
        updateDisplayImage()
    }

    private func applyRedEyeOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Confirm at least one face is present before processing
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: srcCG, options: [:]).perform([req])
            guard let faces = req.results as? [VNFaceObservation], !faces.isEmpty else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            // 2. Apply CIRedEyeCorrection to the full image
            let ciImg = CIImage(cgImage: srcCG)
            guard let filter = CIFilter(name: "CIRedEyeCorrection") else { return }
            filter.setValue(ciImg, forKey: kCIInputImageKey)
            guard let output = filter.outputImage else { return }
            let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            guard let cgResult = ctx.createCGImage(output, from: output.extent) else { return }
            let result = NSImage(cgImage: cgResult, size: source.size)
            let capturedURL = url
            DispatchQueue.main.async {
                self.redEyedImages[capturedURL] = result
                self.setDisplay(base: result, for: capturedURL)
            }
        }
    }

    private func restoreBackground() {
        guard let url = imageLoader.currentImageURL else { return }
        backgroundRemovedImages[url] = nil
        updateDisplayImage()
    }

    private func removeBackgroundOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: srcCG, options: [:])
            let req = VNGenerateForegroundInstanceMaskRequest()
            guard (try? handler.perform([req])) != nil,
                  let result = req.results?.first else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            guard let maskedBuffer = try? result.generateMaskedImage(
                      ofInstances: result.allInstances,
                      from: handler,
                      croppedToInstancesExtent: false) else {
                DispatchQueue.main.async { self.showNoFaceAlert = true }
                return
            }

            let ciImg = CIImage(cvPixelBuffer: maskedBuffer)
            let ctx = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            guard let maskedCG = ctx.createCGImage(ciImg, from: ciImg.extent) else { return }
            let masked = NSImage(cgImage: maskedCG, size: source.size)
            let capturedURL = url
            DispatchQueue.main.async {
                self.backgroundRemovedImages[capturedURL] = masked
                self.setDisplay(base: masked, for: capturedURL)
            }
        }
    }

    private func restoreArtifacts() {
        guard let url = imageLoader.currentImageURL else { return }
        artifactRemovedImages[url] = nil
        updateDisplayImage()
    }

    // swiftlint:disable:next function_body_length
    private func removeArtifactsOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring, !isRemovingArtifacts else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isRemovingArtifacts = true
        artifactRemovalProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            guard let modelURL = Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "SwinIR_color_jpeg40", withExtension: "mlpackage") else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }

            let imgW = srcCG.width
            let imgH = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

            guard let readCtx = CGContext(data: nil, width: imgW, height: imgH,
                                          bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                          space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }
            readCtx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard let pixelData = readCtx.data else {
                DispatchQueue.main.async { self.isRemovingArtifacts = false }
                return
            }
            let pixels = pixelData.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

            let tileSize = 126
            let tileOverlap = 16

            func tileStarts(_ total: Int) -> [Int] {
                guard total > tileSize else { return [0] }
                var positions: [Int] = []
                let stride = tileSize - tileOverlap
                var pos = 0
                while pos < total {
                    if pos + tileSize >= total {
                        positions.append(max(0, total - tileSize))
                        break
                    }
                    positions.append(pos)
                    pos += stride
                }
                return positions
            }

            let xStarts = tileStarts(imgW)
            let yStarts = tileStarts(imgH)
            let totalTiles = xStarts.count * yStarts.count

            var accR = [Float](repeating: 0, count: imgW * imgH)
            var accG = [Float](repeating: 0, count: imgW * imgH)
            var accB = [Float](repeating: 0, count: imgW * imgH)
            var accW = [Float](repeating: 0, count: imgW * imgH)

            var tilesDone = 0

            for y0 in yStarts {
                for x0 in xStarts {
                    let y1 = min(y0 + tileSize, imgH)
                    let x1 = min(x0 + tileSize, imgW)
                    let tileH = y1 - y0
                    let tileW = x1 - x0

                    guard let inArr = try? MLMultiArray(shape: [1, 3, 126, 126], dataType: .float32) else { continue }
                    inArr.withUnsafeMutableBytes { buf, _ in
                        let ptr = buf.bindMemory(to: Float.self)
                        for row in 0..<tileSize {
                            for col in 0..<tileSize {
                                let srcRow = min(y0 + min(row, tileH - 1), imgH - 1)
                                let srcCol = min(x0 + min(col, tileW - 1), imgW - 1)
                                // BGRA byte order (byteOrder32Little + premultipliedFirst)
                                let pixIdx = (srcRow * imgW + srcCol) * 4
                                let pos = row * tileSize + col
                                ptr[0 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 2]) / 255.0 // R
                                ptr[1 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 1]) / 255.0 // G
                                ptr[2 * tileSize * tileSize + pos] = Float(pixels[pixIdx + 0]) / 255.0 // B
                            }
                        }
                    }

                    guard let inFeatures = try? MLDictionaryFeatureProvider(
                              dictionary: ["image": MLFeatureValue(multiArray: inArr)]),
                          let outFeatures = try? model.prediction(from: inFeatures),
                          let outArr = outFeatures.featureValue(for: "restored_image")?.multiArrayValue else { continue }

                    let rampPx = tileOverlap
                    let isFP16 = outArr.dataType == .float16
                    let rawPtr16 = isFP16 ? outArr.dataPointer.bindMemory(to: UInt16.self, capacity: outArr.count) : nil
                    let rawPtr32 = isFP16 ? nil : outArr.dataPointer.bindMemory(to: Float.self, capacity: outArr.count)

                    for ty in 0..<tileH {
                        let gy = y0 + ty
                        for tx in 0..<tileW {
                            let gx = x0 + tx
                            var w: Float = 1.0
                            if rampPx > 0 {
                                if y0 > 0 && ty < rampPx { w *= Float(ty) / Float(rampPx) }
                                if y1 < imgH && ty >= tileH - rampPx { w *= Float(tileH - 1 - ty) / Float(rampPx) }
                                if x0 > 0 && tx < rampPx { w *= Float(tx) / Float(rampPx) }
                                if x1 < imgW && tx >= tileW - rampPx { w *= Float(tileW - 1 - tx) / Float(rampPx) }
                            }
                            let idx = gy * imgW + gx
                            let pos = ty * tileSize + tx
                            let r0: Float, g0: Float, b0: Float
                            if isFP16, let ptr = rawPtr16 {
                                r0 = Float(Float16(bitPattern: ptr[0 * tileSize * tileSize + pos]))
                                g0 = Float(Float16(bitPattern: ptr[1 * tileSize * tileSize + pos]))
                                b0 = Float(Float16(bitPattern: ptr[2 * tileSize * tileSize + pos]))
                            } else if let ptr = rawPtr32 {
                                r0 = ptr[0 * tileSize * tileSize + pos]
                                g0 = ptr[1 * tileSize * tileSize + pos]
                                b0 = ptr[2 * tileSize * tileSize + pos]
                            } else {
                                (r0, g0, b0) = (0, 0, 0)
                            }
                            accR[idx] += r0 * w
                            accG[idx] += g0 * w
                            accB[idx] += b0 * w
                            accW[idx] += w
                        }
                    }

                    tilesDone += 1
                    let progress = Double(tilesDone) / Double(totalTiles)
                    DispatchQueue.main.async { self.artifactRemovalProgress = progress }
                }
            }

            var outPixels = [UInt8](repeating: 255, count: imgW * imgH * 4)
            for i in 0..<(imgW * imgH) {
                let dw = accW[i] > 0 ? accW[i] : 1
                outPixels[i * 4 + 0] = UInt8(min(255, max(0, Int(accB[i] / dw * 255)))) // B
                outPixels[i * 4 + 1] = UInt8(min(255, max(0, Int(accG[i] / dw * 255)))) // G
                outPixels[i * 4 + 2] = UInt8(min(255, max(0, Int(accR[i] / dw * 255)))) // R
                outPixels[i * 4 + 3] = 255 // A
            }

            let capturedURL = url
            outPixels.withUnsafeMutableBytes { ptr in
                guard let outCtx = CGContext(data: ptr.baseAddress, width: imgW, height: imgH,
                                             bitsPerComponent: 8, bytesPerRow: imgW * 4,
                                             space: cs, bitmapInfo: bi),
                      let outCG = outCtx.makeImage() else {
                    DispatchQueue.main.async { self.isRemovingArtifacts = false }
                    return
                }
                let result = NSImage(cgImage: outCG, size: source.size)
                DispatchQueue.main.async {
                    self.artifactRemovedImages[capturedURL] = result
                    self.setDisplay(base: result, for: capturedURL)
                    self.isRemovingArtifacts = false
                }
            }
        }
    }

    // Detects faces via Vision, crops each to 512×512, runs CodeFormer, pastes back.
    // swiftlint:disable:next function_body_length
    private func restoreFacesOnCurrentImage() {
        guard !isProcessing, !isFaceRestoring else { return }
        guard let url = imageLoader.currentImageURL else { return }
        guard let source = upscaledImages[url] ?? sharpenedImages[url] ??
                           smoothedImages[url] ?? enhancedImages[url] ??
                           imageLoader.currentImage else { return }
        guard let srcCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isFaceRestoring = true
        faceRestoreProgress = 0.0

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Detect faces
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: srcCG, options: [:]).perform([req])
            guard let faces = req.results as? [VNFaceObservation], !faces.isEmpty else {
                DispatchQueue.main.async { self.isFaceRestoring = false; self.showNoFaceAlert = true }
                return
            }

            // 2. Load CodeFormer model
            guard let modelURL = Bundle.main.url(forResource: "CodeFormer", withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: "CodeFormer", withExtension: "mlpackage") else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            guard let model = try? MLModel(contentsOf: modelURL, configuration: cfg) else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }

            // 3. Build mutable RGBA context from source
            let imgWidth = srcCG.width, imgHeight = srcCG.height
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(data: nil, width: imgWidth, height: imgHeight,
                                      bitsPerComponent: 8, bytesPerRow: imgWidth * 4,
                                      space: cs, bitmapInfo: bi) else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

            // 4. Process each face
            for (idx, face) in faces.enumerated() {
                // VNFaceObservation.boundingBox: normalized, origin bottom-left → flip Y
                let bb = face.boundingBox
                let faceW = max(1, Int(bb.size.width * CGFloat(imgWidth)))
                let faceH = max(1, Int(bb.size.height * CGFloat(imgHeight)))
                let side = max(faceW, faceH)
                let padded = Int(Double(side) * 1.3)
                let cx = Int(bb.origin.x * CGFloat(imgWidth)) + faceW / 2
                let cy = Int((1 - bb.origin.y - bb.size.height) * CGFloat(imgHeight)) + faceH / 2
                let cropX = max(0, cx - padded / 2)
                let cropY = max(0, cy - padded / 2)
                let cropW = min(imgWidth - cropX, padded)
                let cropH = min(imgHeight - cropY, padded)
                guard cropW > 0, cropH > 0,
                      let cropCG = srcCG.cropping(to: CGRect(x: cropX, y: cropY,
                                                              width: cropW, height: cropH)) else { continue }

                // Scale crop to 512×512 and extract RGBA pixels
                var raw = [UInt8](repeating: 0, count: 512 * 512 * 4)
                raw.withUnsafeMutableBytes { ptr in
                    if let faceCtx = CGContext(data: ptr.baseAddress, width: 512, height: 512,
                                              bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                              space: cs, bitmapInfo: bi) {
                        faceCtx.draw(cropCG, in: CGRect(x: 0, y: 0, width: 512, height: 512))
                    }
                }

                // Build Float16 MLMultiArray [1,3,512,512] NCHW, normalised to [-1,1]
                guard let arr = try? MLMultiArray(shape: [1, 3, 512, 512], dataType: .float16) else { continue }
                arr.withUnsafeMutableBytes { buf, _ in
                    let ptr = buf.bindMemory(to: Float16.self)
                    for i in 0..<(512 * 512) {
                        ptr[0 * 512 * 512 + i] = Float16(Float(raw[i * 4])     / 127.5 - 1)
                        ptr[1 * 512 * 512 + i] = Float16(Float(raw[i * 4 + 1]) / 127.5 - 1)
                        ptr[2 * 512 * 512 + i] = Float16(Float(raw[i * 4 + 2]) / 127.5 - 1)
                    }
                }

                // Run CodeFormer via raw MLModel API (avoids compile-time dependency on generated bindings)
                guard let featureInput = try? MLDictionaryFeatureProvider(
                          dictionary: ["face": MLFeatureValue(multiArray: arr)]),
                      let out = try? model.prediction(from: featureInput),
                      let outArr = out.featureValue(for: "restored_face")?.multiArrayValue else { continue }

                // Convert output [-1,1] Float16 → UInt8 RGBA
                var outRaw = [UInt8](repeating: 255, count: 512 * 512 * 4)
                outArr.withUnsafeBytes { buf in
                    let ptr = buf.bindMemory(to: Float16.self)
                    for i in 0..<(512 * 512) {
                        outRaw[i*4]   = UInt8(min(255, max(0, Int((Float(ptr[0*512*512+i])+1)*127.5))))
                        outRaw[i*4+1] = UInt8(min(255, max(0, Int((Float(ptr[1*512*512+i])+1)*127.5))))
                        outRaw[i*4+2] = UInt8(min(255, max(0, Int((Float(ptr[2*512*512+i])+1)*127.5))))
                    }
                }

                // Paste restored face back at crop region.
                // cropY is top-down; CGContext origin is bottom-left, so convert.
                let pasteY = imgHeight - cropY - cropH
                outRaw.withUnsafeMutableBytes { ptr in
                    if let restoredCtx = CGContext(data: ptr.baseAddress, width: 512, height: 512,
                                                   bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                                   space: cs, bitmapInfo: bi),
                       let restoredCG = restoredCtx.makeImage() {
                        ctx.draw(restoredCG, in: CGRect(x: cropX, y: pasteY, width: cropW, height: cropH))
                    }
                }

                let progress = Double(idx + 1) / Double(faces.count)
                DispatchQueue.main.async { self.faceRestoreProgress = progress }
            }

            guard let finalCG = ctx.makeImage() else {
                DispatchQueue.main.async { self.isFaceRestoring = false }
                return
            }
            let result = NSImage(cgImage: finalCG, size: NSSize(width: imgWidth, height: imgHeight))
            let capturedURL = url
            DispatchQueue.main.async {
                self.faceRestoredImages[capturedURL] = result
                self.isFaceRestoring = false
                self.setDisplay(base: result, for: capturedURL)
            }
        }
    }

    private func toggleInfoOverlay() {
        guard let url = imageLoader.currentImageURL else { return }
        if infoOverlayURLs.contains(url) {
            infoOverlayURLs.remove(url)
        } else {
            infoOverlayURLs.insert(url)
            if imageInfoCache[url] == nil {
                Task.detached(priority: .userInitiated) {
                    let info = Self.loadImageInfo(for: url)
                    await MainActor.run {
                        self.imageInfoCache[url] = info
                    }
                }
            }
        }
    }

    private static func loadImageInfo(for url: URL) -> ImageInfo? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let fileSize = attrs[.size] as? Int64 ?? 0
        let fileSizeText = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        let dateTakenText: String
        if let exifDateStr = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = parser.date(from: exifDateStr) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                dateTakenText = formatter.string(from: date)
            } else {
                dateTakenText = exifDateStr
            }
        } else if let modDate = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateTakenText = formatter.string(from: modDate)
        } else {
            dateTakenText = "Unknown"
        }

        let make = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff?[kCGImagePropertyTIFFModel as String] as? String
        let cameraText: String?
        if let make, let model {
            if model.localizedCaseInsensitiveContains(make) {
                cameraText = model
            } else {
                cameraText = "\(make) \(model)"
            }
        } else {
            cameraText = model ?? make
        }

        return ImageInfo(width: width, height: height, fileSizeText: fileSizeText, dateTakenText: dateTakenText, cameraText: cameraText)
    }

    private func renameCurrentImage() {
        guard let url = imageLoader.currentImageURL else { return }
        let ext = url.pathExtension
        let basename = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()

        let alert = NSAlert()
        alert.messageText = "Rename Image"
        alert.informativeText = "Enter a new name for \"\(url.lastPathComponent)\":"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = basename

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.isHidden = true

        let stackView = NSStackView(views: [textField, errorLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 300),
        ])
        alert.accessoryView = stackView

        let renameButton = alert.buttons[0]

        let validate = {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if let error = validateRenameTarget(newName: newName, ext: ext, directory: directory, originalBasename: basename) {
                renameButton.isEnabled = false
                errorLabel.stringValue = error
                errorLabel.isHidden = false
            } else {
                renameButton.isEnabled = !newName.isEmpty
                errorLabel.isHidden = true
            }
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: textField,
            queue: .main
        ) { _ in
            validate()
        }

        guard let window = myWindow ?? NSApplication.shared.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            NotificationCenter.default.removeObserver(observer)
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }

            let newURL = directory.appendingPathComponent("\(newName).\(ext)")
            guard newURL != url else { return }

            do {
                try FileManager.default.moveItem(at: url, to: newURL)

                if let val = self.rotationAngles.removeValue(forKey: url) { self.rotationAngles[newURL] = val }
                if let val = self.enhancedImages.removeValue(forKey: url) { self.enhancedImages[newURL] = val }
                if let val = self.smoothedImages.removeValue(forKey: url) { self.smoothedImages[newURL] = val }
                if let val = self.sharpenedImages.removeValue(forKey: url) { self.sharpenedImages[newURL] = val }
                if let val = self.upscaledImages.removeValue(forKey: url) { self.upscaledImages[newURL] = val }
                if let val = self.upscaleFactors.removeValue(forKey: url) { self.upscaleFactors[newURL] = val }
                if let val = self.savedZoomScales.removeValue(forKey: url) { self.savedZoomScales[newURL] = val }
                if let val = self.savedPanOffsets.removeValue(forKey: url) { self.savedPanOffsets[newURL] = val }
                if self.infoOverlayURLs.remove(url) != nil { self.infoOverlayURLs.insert(newURL) }
                if let val = self.imageInfoCache.removeValue(forKey: url) { self.imageInfoCache[newURL] = val }

                let oldKey = url.absoluteString
                if self.favouriteURLStrings.remove(oldKey) != nil {
                    self.favouriteURLStrings.insert(newURL.absoluteString)
                    self.saveFavourites()
                    if self.showFavouritesOnly {
                        self.updateFavouritesFilter()
                    }
                }

                if self.lastDisplayedURL == url {
                    self.lastDisplayedURL = newURL
                }

                self.imageLoader.renameImage(from: url, to: newURL)
                self.windowTitle = Self.titleForImage(at: newURL)

                let message = "Renamed to \"\(newURL.lastPathComponent)\""
                self.savedToast = message
                self.savedToastIsError = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.savedToast == message { self.savedToast = nil }
                }

                self.myWindow?.undoManager?.registerUndo(withTarget: self.imageLoader) { _ in
                    do {
                        try FileManager.default.moveItem(at: newURL, to: url)

                        if let val = self.rotationAngles.removeValue(forKey: newURL) { self.rotationAngles[url] = val }
                        if let val = self.enhancedImages.removeValue(forKey: newURL) { self.enhancedImages[url] = val }
                        if let val = self.smoothedImages.removeValue(forKey: newURL) { self.smoothedImages[url] = val }
                        if let val = self.sharpenedImages.removeValue(forKey: newURL) { self.sharpenedImages[url] = val }
                        if let val = self.upscaledImages.removeValue(forKey: newURL) { self.upscaledImages[url] = val }
                        if let val = self.upscaleFactors.removeValue(forKey: newURL) { self.upscaleFactors[url] = val }
                        if let val = self.savedZoomScales.removeValue(forKey: newURL) { self.savedZoomScales[url] = val }
                        if let val = self.savedPanOffsets.removeValue(forKey: newURL) { self.savedPanOffsets[url] = val }
                        if self.infoOverlayURLs.remove(newURL) != nil { self.infoOverlayURLs.insert(url) }
                        if let val = self.imageInfoCache.removeValue(forKey: newURL) { self.imageInfoCache[url] = val }

                        let renamedKey = newURL.absoluteString
                        if self.favouriteURLStrings.remove(renamedKey) != nil {
                            self.favouriteURLStrings.insert(url.absoluteString)
                            self.saveFavourites()
                            if self.showFavouritesOnly { self.updateFavouritesFilter() }
                        }

                        if self.lastDisplayedURL == newURL { self.lastDisplayedURL = url }

                        self.imageLoader.renameImage(from: newURL, to: url)
                        self.windowTitle = Self.titleForImage(at: url)

                        let undoMessage = "Renamed back to \"\(url.lastPathComponent)\""
                        self.savedToast = undoMessage
                        self.savedToastIsError = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            if self.savedToast == undoMessage { self.savedToast = nil }
                        }
                    } catch {
                        self.showErrorToast("Undo failed: \(error.localizedDescription)")
                    }
                }
                self.myWindow?.undoManager?.setActionName("Rename")
            } catch {
                self.showErrorToast("Rename failed: \(error.localizedDescription)")
            }
        }
        textField.selectText(nil)
    }

    private func moveCurrentImageToTrash() {
        guard let url = imageLoader.currentImageURL else { return }
        let filename = url.lastPathComponent

        let alert = NSAlert()
        alert.messageText = "Move \"\(filename)\" to Trash?"
        alert.informativeText = "You can restore this file from the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        if let window = myWindow ?? NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    let imageIndex = self.imageLoader.imageURLs.firstIndex(of: url) ?? 0
                    let allIndex = self.imageLoader.allImageURLs.firstIndex(of: url) ?? 0
                    let savedRotation = self.rotationAngles[url]
                    let savedEnhanced = self.enhancedImages[url]
                    let savedSmoothed = self.smoothedImages[url]
                    let savedSharpened = self.sharpenedImages[url]
                    let savedUpscaled = self.upscaledImages[url]
                    let savedUpscaleFactor = self.upscaleFactors[url]
                    let savedZoom = self.savedZoomScales[url]
                    let savedPan = self.savedPanOffsets[url]
                    let hadInfoOverlay = self.infoOverlayURLs.contains(url)
                    let savedInfo = self.imageInfoCache[url]
                    let wasFavourite = self.favouriteURLStrings.contains(url.absoluteString)

                    do {
                        var trashResultURL: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &trashResultURL)
                        self.rotationAngles[url] = nil
                        self.enhancedImages[url] = nil
                        self.smoothedImages[url] = nil
                        self.sharpenedImages[url] = nil
                        self.upscaledImages[url] = nil
                        self.upscaleFactors[url] = nil
                        self.savedZoomScales[url] = nil
                        self.savedPanOffsets[url] = nil
                        self.infoOverlayURLs.remove(url)
                        self.imageInfoCache[url] = nil
                        self.imageLoader.removeImage(at: url)

                        if let trashedTo = trashResultURL as URL? {
                            self.myWindow?.undoManager?.registerUndo(withTarget: self.imageLoader) { _ in
                                do {
                                    try FileManager.default.moveItem(at: trashedTo, to: url)
                                    self.imageLoader.insertImage(url: url, at: imageIndex, allIndex: allIndex)
                                    if let v = savedRotation { self.rotationAngles[url] = v }
                                    if let v = savedEnhanced { self.enhancedImages[url] = v }
                                    if let v = savedSmoothed { self.smoothedImages[url] = v }
                                    if let v = savedSharpened { self.sharpenedImages[url] = v }
                                    if let v = savedUpscaled { self.upscaledImages[url] = v }
                                    if let v = savedUpscaleFactor { self.upscaleFactors[url] = v }
                                    if let v = savedZoom { self.savedZoomScales[url] = v }
                                    if let v = savedPan { self.savedPanOffsets[url] = v }
                                    if hadInfoOverlay { self.infoOverlayURLs.insert(url) }
                                    if let v = savedInfo { self.imageInfoCache[url] = v }
                                    if wasFavourite {
                                        self.favouriteURLStrings.insert(url.absoluteString)
                                        self.saveFavourites()
                                        if self.showFavouritesOnly { self.updateFavouritesFilter() }
                                    }
                                    self.rotationAngle = self.currentURLRotation()
                                    self.updateDisplayImage()
                                    if let current = self.imageLoader.currentImageURL {
                                        self.windowTitle = Self.titleForImage(at: current)
                                    }
                                    let message = "Restored \"\(url.lastPathComponent)\""
                                    self.savedToast = message
                                    self.savedToastIsError = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        if self.savedToast == message { self.savedToast = nil }
                                    }
                                } catch {
                                    self.showErrorToast("Undo failed: \(error.localizedDescription)")
                                }
                            }
                            self.myWindow?.undoManager?.setActionName("Move to Trash")
                        }
                    } catch {
                        self.showErrorToast("Failed to trash: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func pickDestinationFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select destination folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    private func copyCurrentImageToFolder() {
        guard let sourceURL = imageLoader.currentImageURL else { return }
        pickDestinationFolder { destDir in
            let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                let folderName = destDir.lastPathComponent
                let message = "Copied to \(folderName)"
                self.savedToast = message
                self.savedToastIsError = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.savedToast == message { self.savedToast = nil }
                }
            } catch {
                self.showErrorToast("Copy failed: \(error.localizedDescription)")
            }
        }
    }

    private func moveCurrentImageToFolder() {
        guard let sourceURL = imageLoader.currentImageURL else { return }
        pickDestinationFolder { destDir in
            let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destURL)
                let folderName = destDir.lastPathComponent
                let message = "Moved to \(folderName)"
                self.savedToast = message
                self.savedToastIsError = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.savedToast == message { self.savedToast = nil }
                }
                self.rotationAngles[sourceURL] = nil
                self.enhancedImages[sourceURL] = nil
                self.smoothedImages[sourceURL] = nil
                self.sharpenedImages[sourceURL] = nil
                self.upscaledImages[sourceURL] = nil
                self.upscaleFactors[sourceURL] = nil
                self.savedZoomScales[sourceURL] = nil
                self.savedPanOffsets[sourceURL] = nil
                self.infoOverlayURLs.remove(sourceURL)
                self.imageInfoCache[sourceURL] = nil
                self.imageLoader.removeImage(at: sourceURL)
            } catch {
                self.showErrorToast("Move failed: \(error.localizedDescription)")
            }
        }
    }

    private func copyImageToClipboard() {
        guard let displayedImage = currentDisplayImage ?? imageLoader.currentImage else { return }
        let outputImage = applyRotationIfNeeded(displayedImage)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([outputImage])
        let message = "Copied to clipboard"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if savedToast == message { savedToast = nil }
        }
    }

    private func copyFilePathToClipboard() {
        guard let url = imageLoader.currentImageURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        let message = "Path copied to clipboard"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if savedToast == message { savedToast = nil }
        }
    }

    private func revealCurrentImageInFinder() {
        guard let url = imageLoader.currentImageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openCurrentImageInDefaultApp() {
        guard let url = imageLoader.currentImageURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func showOpenWithMenu() {
        guard let url = imageLoader.currentImageURL,
              let window = myWindow ?? NSApplication.shared.keyWindow,
              let contentView = window.contentView else { return }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        guard !apps.isEmpty else { return }
        let menu = NSMenu(title: "Open With")
        let delegate = OpenWithMenuDelegate(imageURL: url)
        OpenWithMenuDelegate.current = delegate
        for appURL in apps {
            let name = FileManager.default.displayName(atPath: appURL.path)
            let item = NSMenuItem(title: name, action: #selector(OpenWithMenuDelegate.openWith(_:)),
                                  keyEquivalent: "")
            item.representedObject = appURL
            item.target = delegate
            menu.addItem(item)
        }
        let mouseLocation = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: mouseLocation)
        let viewPoint = contentView.convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: contentView)
    }

    /// Writes the currently-displayed image (with rotation baked in) to a
    /// sibling PNG named `<basename>_edited.png`. Overwrites if it exists.
    /// The original file is never touched. If the source volume is read-only
    /// (e.g. a mounted disk image), falls back to NSSavePanel so the user
    /// can pick a writable location.
    private func saveEditedImage() {
        guard let originalURL = imageLoader.currentImageURL else { return }
        guard let displayedImage = currentDisplayImage ?? imageLoader.currentImage else { return }

        let outputImage = applyRotationIfNeeded(displayedImage)

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let suggestedName = "\(baseName)_edited.png"

        guard let pngData = encodePNG(outputImage) else {
            showErrorToast("Could not encode image as PNG")
            return
        }

        let parentDir = originalURL.deletingLastPathComponent()
        if isVolumeWritable(parentDir) {
            let outputURL = parentDir.appendingPathComponent(suggestedName)
            do {
                try pngData.write(to: outputURL)
                showSavedToast(filename: outputURL.lastPathComponent)
                return
            } catch {
                // Volume claimed writable but write still failed (permissions,
                // disk full, etc.). Fall through to the panel so the user
                // can pick a different location instead of being stuck.
                debugOutput += "In-place save failed: \(error.localizedDescription)\n"
            }
        }

        promptSaveAs(suggestedName: suggestedName, data: pngData)
    }

    private func encodePNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func isVolumeWritable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly != true
    }

    private func promptSaveAs(suggestedName: String, data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png]
        panel.message = "The source folder is read-only (mounted disk image or similar). Choose a writable location."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                showSavedToast(filename: url.lastPathComponent)
            } catch {
                showErrorToast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Bakes the current rotation angle into a fresh NSImage so the saved
    /// file matches what the user sees. Returns the input untouched if no
    /// rotation is applied.
    private func applyRotationIfNeeded(_ image: NSImage) -> NSImage {
        let degrees = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
        if degrees == 0 { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let radians = CGFloat(rotationAngle.radians)
        let originalSize = CGSize(width: cgImage.width, height: cgImage.height)
        let cosV = abs(cos(radians))
        let sinV = abs(sin(radians))
        let newSize = CGSize(
            width: originalSize.width * cosV + originalSize.height * sinV,
            height: originalSize.width * sinV + originalSize.height * cosV
        )
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width.rounded()),
            height: Int(newSize.height.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // SwiftUI .rotationEffect(positive) is clockwise on screen; CGContext
        // positive rotation is counter-clockwise, so flip the sign.
        context.rotate(by: -radians)
        context.draw(cgImage, in: CGRect(
            x: -originalSize.width / 2,
            y: -originalSize.height / 2,
            width: originalSize.width,
            height: originalSize.height
        ))
        guard let rotated = context.makeImage() else { return image }
        return NSImage(cgImage: rotated, size: newSize)
    }

    private func showSavedToast(filename: String) {
        let message = "Saved as \(filename)"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Don't clear a newer toast that landed during our delay.
            if savedToast == message { savedToast = nil }
        }
    }

    private func showErrorToast(_ message: String) {
        savedToast = message
        savedToastIsError = true
        // Errors stay up a bit longer so the user can read them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if savedToast == message { savedToast = nil }
        }
    }

    private func toggleFavourite() {
        guard let url = imageLoader.currentImageURL else { return }
        let key = url.absoluteString
        let wasFavourite = favouriteURLStrings.contains(key)
        if wasFavourite {
            favouriteURLStrings.remove(key)
        } else {
            favouriteURLStrings.insert(key)
        }
        saveFavourites()
        if showFavouritesOnly {
            updateFavouritesFilter()
        }
        let message = wasFavourite ? "Unfavourited" : "★ Favourited"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if savedToast == message { savedToast = nil }
        }
    }

    private func toggleShowFavouritesOnly() {
        showFavouritesOnly.toggle()
        updateFavouritesFilter()
        let message = showFavouritesOnly ? "★ Favourites only" : "Showing all images"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if savedToast == message { savedToast = nil }
        }
    }

    private func updateFavouritesFilter() {
        if showFavouritesOnly {
            let favs = favouriteURLStrings
            imageLoader.urlFilter = { url in
                favs.contains(url.absoluteString)
            }
        } else {
            imageLoader.urlFilter = nil
        }
    }

    private func loadFavourites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "favouriteImages") {
            favouriteURLStrings = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: "rotationAngles") as? [String: Double] {
            for (key, val) in saved {
                if let url = URL(string: key) {
                    rotationAngles[url] = Angle(degrees: val)
                }
            }
        }
        enhancedURLStrings = Set(UserDefaults.standard.stringArray(forKey: "enhancedImages") ?? [])
        smoothedURLStrings = Set(UserDefaults.standard.stringArray(forKey: "smoothedImages") ?? [])
        sharpenedURLStrings = Set(UserDefaults.standard.stringArray(forKey: "sharpenedImages") ?? [])
        denoiseURLLevels = (UserDefaults.standard.dictionary(forKey: "denoiseURLLevels") as? [String: Double]) ?? [:]
        flippedHorizontally = Set(UserDefaults.standard.stringArray(forKey: "flippedHorizontally") ?? [])
        flippedVertically = Set(UserDefaults.standard.stringArray(forKey: "flippedVertically") ?? [])
        vignetteURLLevels = (UserDefaults.standard.dictionary(forKey: "vignetteURLLevels") as? [String: Double]) ?? [:]
        if let data = UserDefaults.standard.data(forKey: "adjustmentURLLevels"),
           let decoded = try? JSONDecoder().decode([String: ImageAdjustments].self, from: data) {
            adjustmentURLLevels = decoded
        }
        let rawEffects = (UserDefaults.standard.dictionary(forKey: "photoEffects") as? [String: String]) ?? [:]
        imageEffects = Dictionary(uniqueKeysWithValues: rawEffects.compactMap { key, val -> (URL, String)? in
            guard let url = URL(string: key) else { return nil }
            return (url, val)
        })
    }

    private func saveFavourites() {
        UserDefaults.standard.set(Array(favouriteURLStrings), forKey: "favouriteImages")
        let rotDict = Dictionary(uniqueKeysWithValues: rotationAngles.map { ($0.key.absoluteString, $0.value.degrees) })
        UserDefaults.standard.set(rotDict, forKey: "rotationAngles")
        UserDefaults.standard.set(Array(enhancedURLStrings), forKey: "enhancedImages")
        UserDefaults.standard.set(Array(smoothedURLStrings), forKey: "smoothedImages")
        UserDefaults.standard.set(Array(sharpenedURLStrings), forKey: "sharpenedImages")
        UserDefaults.standard.set(denoiseURLLevels, forKey: "denoiseURLLevels")
        UserDefaults.standard.set(Array(flippedHorizontally), forKey: "flippedHorizontally")
        UserDefaults.standard.set(Array(flippedVertically), forKey: "flippedVertically")
        UserDefaults.standard.set(vignetteURLLevels, forKey: "vignetteURLLevels")
        if let data = try? JSONEncoder().encode(adjustmentURLLevels) {
            UserDefaults.standard.set(data, forKey: "adjustmentURLLevels")
        }
        let effectsDict = Dictionary(uniqueKeysWithValues: imageEffects.map { ($0.key.absoluteString, $0.value) })
        UserDefaults.standard.set(effectsDict, forKey: "photoEffects")
    }

    @ViewBuilder private var directoryMissingOverlay: some View {
        if imageLoader.directoryMissing {
            VStack(spacing: 20) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.7))
                Text("Directory is no longer available")
                    .font(.title2)
                    .foregroundColor(.white)
                if let dir = selectedDirectory {
                    Text(dir.path)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                Text("Waiting for the directory to reappear…")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Directory is no longer available. Waiting for the directory to reappear.")
            .padding(40)
            .background(.black.opacity(0.85))
            .cornerRadius(12)
        }
    }

}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    init(countLimit: Int = 500) {
        cache.countLimit = countLimit
    }

    func get(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ url: URL, image: NSImage) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct ThumbnailCell: View {
    let url: URL
    let size: CGFloat
    let isSelected: Bool
    let isFavourite: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Color.gray.opacity(0.2)
                        .frame(width: size, height: size)
                }

                if isFavourite {
                    VStack {
                        HStack {
                            Spacer()
                            Text("★")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                                .shadow(color: .black, radius: 2)
                                .padding(2)
                        }
                        Spacer()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thumbnailAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Double tap to view this image")
        .task(id: url) {
            await loadThumbnail()
        }
    }

    private var thumbnailAccessibilityLabel: String {
        var label = url.lastPathComponent
        if isFavourite { label += ", favourited" }
        if isSelected { label += ", selected" }
        return label
    }

    @MainActor
    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.get(url) {
            self.thumbnail = cached
            return
        }
        let maxPixel = Int(size * 2)
        let target = url

        // Debounce: cells scrolled past in under 50 ms cancel here (Task.sleep
        // throws on cancellation) instead of spawning a disk-read task.
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }

        let thumb = await Task.detached(priority: .utility) {
            return Self.generate(url: target, maxPixelSize: maxPixel)
        }.value
        // Cell may have been recycled to a different URL while we were
        // generating — only commit if we're still the cell for `target`.
        guard target == url else { return }
        if let thumb {
            ThumbnailCache.shared.set(target, image: thumb)
            self.thumbnail = thumb
        }
    }

    /// Uses ImageIO to read just the embedded/scaled thumbnail rather than
    /// decoding the full image. Cheap even for very large source files.
    nonisolated private static func generate(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct ThumbnailStrip: View {
    @ObservedObject var imageLoader: ImageLoader
    var favouriteURLStrings: Set<String> = []
    let onSelect: (Int) -> Void

    private let thumbSize: CGFloat = 80

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(imageLoader.imageURLs.enumerated()), id: \.element) { pair in
                        ThumbnailCell(
                            url: pair.element,
                            size: thumbSize,
                            isSelected: pair.offset == imageLoader.currentIndex,
                            isFavourite: favouriteURLStrings.contains(pair.element.absoluteString),
                            onTap: { onSelect(pair.offset) }
                        )
                        .id(pair.element)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(height: thumbSize + 16)
            .background(.black.opacity(0.75))
            .accessibilityLabel("Thumbnail strip, \(imageLoader.imageURLs.count) images")
            .onChange(of: imageLoader.currentIndex) { _, _ in
                DispatchQueue.main.async {
                    if let url = imageLoader.currentImageURL {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(url, anchor: .center)
                        }
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let url = imageLoader.currentImageURL {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }
}

#Preview {
    SlideshowView()
        .environmentObject(RecentDirectories())
}
