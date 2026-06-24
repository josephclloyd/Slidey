import SwiftUI
import AppKit
import CoreImage
import IOKit.pwr_mgt
import UniformTypeIdentifiers

struct ImageInfo {
    let width: Int
    let height: Int
    let fileSizeText: String
    let dateTakenText: String
    let cameraText: String?
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
    @State private var upscaledImages: [URL: NSImage] = [:]
    @State private var savedZoomScales: [URL: CGFloat] = [:]
    @State private var savedPanOffsets: [URL: CGSize] = [:]
    @State private var currentDisplayImage: NSImage?
    @State private var myWindow: NSWindow?
    @State private var windowHasFocus = false
    @State private var isProcessing = false
    @State private var debugOutput = ""
    @State private var showDebugWindow = false
    @State private var showFilename = false
    @State private var upscaleProcess: Process?
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
    @State private var isAutoOpening = false
    @State private var showKeyboardShortcuts = false
    @State private var favouriteURLStrings: Set<String> = []
    @State private var showFavouritesOnly: Bool = false

    private var effectiveDisplayImage: NSImage? {
        currentDisplayImage ?? imageLoader.currentImage
    }

    @ViewBuilder private var emptyStateContent: some View {
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
            .onAppear {
                captureWindow()
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
                captureWindow()
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
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                captureWindow()
            }
        }
    }

    @ViewBuilder private var imageDisplayContent: some View {
        @Bindable var zoomPan = zoomPan
        GeometryReader { geometry in
            if let image = currentDisplayImage {
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
                .id(imageLoader.currentImageURL)
                .transition(.opacity)
                .onAppear {
                    zoomPan.windowSize = geometry.size
                    updateDisplayImage()
                    captureWindow()
                }
                .onChange(of: geometry.size) { _, newSize in
                    zoomPan.windowSize = newSize
                }
            }
        }
        .animation(transitionsEnabled ? .easeInOut(duration: transitionDuration) : nil, value: imageLoader.currentImageURL)
    }

    @ViewBuilder private var overlayViews: some View {
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
                        Text("\(info.width) \u{00d7} \(info.height) px")
                        Text(info.fileSizeText)
                        Text(info.dateTakenText)
                        if let camera = info.cameraText {
                            Text(camera)
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
                    Text("AI Upscaling Image (4x)…")
                        .font(.headline)
                        .foregroundColor(.white)

                    ProgressView(value: upscaleProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 220)

                    Text("\(Int(upscaleProgress * 100))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    Button("Cancel", action: cancelUpscale)
                        .buttonStyle(.bordered)
                        .tint(.white)
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
    }

    var body: some View {
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
            if !isEmpty {
                isAutoOpening = false
                rotationAngle = currentURLRotation()
                updateDisplayImage()
                enterFullScreen()
                musicManager.activate()

            } else {
                slideshow.stop()
                musicManager.deactivate()
            }
            updateCursorVisibility()
        }
        .onChange(of: imageLoader.imageURLs) { _, newURLs in
            // Drop any per-URL session state for files that no longer exist
            // in the directory (deleted on disk, or we switched folders).
            // Use allImageURLs so filtering doesn't discard state for hidden images.
            let valid = imageLoader.allImageURLs.isEmpty ? Set(newURLs) : Set(imageLoader.allImageURLs)
            rotationAngles = rotationAngles.filter { valid.contains($0.key) }
            enhancedImages = enhancedImages.filter { valid.contains($0.key) }
            smoothedImages = smoothedImages.filter { valid.contains($0.key) }
            upscaledImages = upscaledImages.filter { valid.contains($0.key) }
            savedZoomScales = savedZoomScales.filter { valid.contains($0.key) }
            savedPanOffsets = savedPanOffsets.filter { valid.contains($0.key) }
            infoOverlayURLs = infoOverlayURLs.intersection(valid)
            imageInfoCache = imageInfoCache.filter { valid.contains($0.key) }

            rotationAngle = currentURLRotation()
            if !newURLs.isEmpty {
                updateDisplayImage()
            }
        }
        .onChange(of: imageLoader.currentIndex) { _, _ in
            // Only change zoom/pan when the displayed *file* changes. A rescan
            // can shift currentIndex while keeping the same file under the
            // cursor; that shouldn't yank the user out of their zoom.
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
            }
            rotationAngle = currentURLRotation()
            updateDisplayImage()
            // Reset the auto-advance clock on every navigation (manual or
            // auto) so the next tick is always `interval` from now.
            if slideshow.isPlaying { slideshow.reschedule(interval: slideshowInterval) { [imageLoader] in imageLoader.nextImage() } }
        }
        .onChange(of: isFullScreen) { _, fullScreen in
            updateCursorVisibility()
            if fullScreen {
                acquireDisplaySleepAssertion()
                musicManager.activate()
            } else {
                releaseDisplaySleepAssertion()
                musicManager.deactivate()
            }
        }
        .onChange(of: showThumbnails) { _, _ in
            updateCursorVisibility()
        }
        .onChange(of: sortOrder, initial: true) { _, newValue in
            imageLoader.sortOrder = newValue
            if !imageLoader.imageURLs.isEmpty {
                imageLoader.applySort()
            }
        }
        .onAppear {
            loadFavourites()
            consumePendingOpenIfPossible()
            scheduleAutoOpenRecent()
        }
        .onDisappear {
            slideshow.stop()
            releaseDisplaySleepAssertion()
            musicManager.deactivate()
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
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.upscaleImage)) { _ in
            ifKeyWindow { upscaleCurrentImage() }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyImage)) { _ in
            ifKeyWindow { copyImageToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyFilePath)) { _ in
            ifKeyWindow { copyFilePathToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.revealInFinder)) { _ in
            ifKeyWindow { revealCurrentImageInFinder() }
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
            imageLoader.jumpTo(index: 0)
            return .handled
        }

        if key == .end {
            imageLoader.jumpTo(index: imageLoader.imageURLs.count - 1)
            return .handled
        }

        if zoomPan.zoomScale > 1.0 {
            switch key {
            case .leftArrow:
                if zoomPan.canPan(direction: .left, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    zoomPan.imageOffset.width += 50
                } else {
                    imageLoader.previousImage()
                }
                return .handled
            case .rightArrow:
                if zoomPan.canPan(direction: .right, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    zoomPan.imageOffset.width -= 50
                } else {
                    imageLoader.nextImage()
                }
                return .handled
            case .upArrow:
                if zoomPan.canPan(direction: .up, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    zoomPan.imageOffset.height += 50
                }
                return .handled
            case .downArrow:
                if zoomPan.canPan(direction: .down, image: effectiveDisplayImage, rotationAngle: rotationAngle) {
                    zoomPan.imageOffset.height -= 50
                }
                return .handled
            default:
                break
            }
        } else {
            switch key {
            case .leftArrow:
                imageLoader.previousImage()
                return .handled
            case .rightArrow:
                imageLoader.nextImage()
                return .handled
            default:
                break
            }
        }

        switch keyPress.characters {
        case "+", "=":
            zoomPan.zoomScale = min(zoomPan.zoomScale * 1.2, 10.0)
            return .handled
        case "-", "_":
            zoomPan.zoomScale = max(zoomPan.zoomScale / 1.2, 0.1)
            if zoomPan.zoomScale <= 1.0 {
                zoomPan.reset()
            }
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
        case "u":
            upscaleCurrentImage()
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
        // Hide cursor only if: images are loaded AND fullscreen AND window has focus
        let shouldHideCursor = !imageLoader.imageURLs.isEmpty && isFullScreen && windowHasFocus && !showThumbnails

        DispatchQueue.main.async {
            if shouldHideCursor {
                NSCursor.hide()
            } else {
                NSCursor.unhide()
            }
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

        // Reset all image modifications
        rotationAngles = [:]
        rotationAngle = .zero
        enhancedImages = [:]
        smoothedImages = [:]
        upscaledImages = [:]
        savedZoomScales = [:]
        savedPanOffsets = [:]
        infoOverlayURLs = []
        imageInfoCache = [:]
        zoomPan.reset()

        imageLoader.loadImagesFromDirectory(url: url, jumpTo: targetURL)
        windowTitle = url.lastPathComponent
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
        }
    }

    private func rotateCounterClockwise() {
        rotationAngle = Angle(degrees: rotationAngle.degrees - 90)
        if let url = imageLoader.currentImageURL {
            rotationAngles[url] = rotationAngle
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

    private func updateDisplayImage() {
        guard let url = imageLoader.currentImageURL else {
            currentDisplayImage = imageLoader.currentImage
            return
        }
        // Priority: upscaled > smoothed > enhanced > original
        if let upscaled = upscaledImages[url] {
            currentDisplayImage = upscaled
        } else if let smoothed = smoothedImages[url] {
            currentDisplayImage = smoothed
        } else if let enhanced = enhancedImages[url] {
            currentDisplayImage = enhanced
        } else {
            currentDisplayImage = imageLoader.currentImage
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
            invalidateUpscaling(for: url)
            currentDisplayImage = enhancedNSImage
        }
    }

    private func removeEnhancement() {
        guard let url = imageLoader.currentImageURL else { return }
        enhancedImages[url] = nil
        invalidateUpscaling(for: url)
        updateDisplayImage()
    }

    private func smoothCurrentImage() {
        guard let originalImage = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CINoiseReduction") else { return }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: "inputSharpness")

        guard let outputImage = filter.outputImage else { return }

        let context = CIContext()
        if let smoothedCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let smoothedNSImage = NSImage(cgImage: smoothedCGImage, size: originalImage.size)
            guard let url = imageLoader.currentImageURL else { return }
            smoothedImages[url] = smoothedNSImage
            invalidateUpscaling(for: url)
            currentDisplayImage = smoothedNSImage
        }
    }

    private func removeSmoothing() {
        guard let url = imageLoader.currentImageURL else { return }
        smoothedImages[url] = nil
        invalidateUpscaling(for: url)
        updateDisplayImage()
    }

    private func upscaleCurrentImage() {
        guard !isProcessing else { return }
        guard let targetURL = imageLoader.currentImageURL else { return }
        // Upscale the best non-upscaled version: smoothed > enhanced > original
        guard let sourceImage = smoothedImages[targetURL] ?? enhancedImages[targetURL] ?? imageLoader.currentImage else { return }

        isProcessing = true
        upscaleCancelled = false
        upscaleProgress = 0
        debugOutput = "Starting upscale process...\n"
        let originalImage = sourceImage

        // Create temp files with a unique per-run prefix so concurrent upscales
        // don't collide and so a local attacker can't pre-create a symlink at a
        // predictable path to redirect the binary's write.
        let tempDir = FileManager.default.temporaryDirectory
        let runID = UUID().uuidString
        let inputPath = tempDir.appendingPathComponent("realesrgan_\(runID)_input.png")
        let outputPath = tempDir.appendingPathComponent("realesrgan_\(runID)_output.png")

        debugOutput += "Temp input: \(inputPath.path)\n"
        debugOutput += "Temp output: \(outputPath.path)\n"

        // Save image to temp file
        guard let tiffData = originalImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            debugOutput += "ERROR: Failed to convert image to PNG\n"
            isProcessing = false
            return
        }

        do {
            try pngData.write(to: inputPath)
            debugOutput += "Saved input image (\(pngData.count) bytes)\n"
        } catch {
            debugOutput += "ERROR writing temp input file: \(error)\n"
            isProcessing = false
            return
        }

        // Get paths from bundle - try multiple lookup methods
        var executablePath: String?
        var modelsPath: String?

        // First, show bundle info
        let bundlePath = Bundle.main.resourcePath
        debugOutput += "Bundle resource path: \(bundlePath ?? "nil")\n"

        if let bundlePath = bundlePath {
            // List what's actually in the bundle
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                debugOutput += "Bundle contents: \(contents.joined(separator: ", "))\n"
            } catch {
                debugOutput += "Error listing bundle contents: \(error)\n"
            }
        }

        // Method 1: Try with Resources directory
        executablePath = Bundle.main.path(forResource: "realesrgan-ncnn-vulkan", ofType: "", inDirectory: "Resources")
        modelsPath = Bundle.main.path(forResource: "models", ofType: nil, inDirectory: "Resources")

        if executablePath != nil {
            debugOutput += "Method 1 success: Found in Resources/\n"
        }

        // Method 2: Try without Resources directory
        if executablePath == nil {
            executablePath = Bundle.main.path(forResource: "realesrgan-ncnn-vulkan", ofType: "")
            if executablePath != nil {
                debugOutput += "Method 2 success: Found at root level\n"
            }
        }
        if modelsPath == nil {
            modelsPath = Bundle.main.path(forResource: "models", ofType: nil)
        }

        // Method 3: Try direct bundle resource path
        if executablePath == nil, let bundlePath = bundlePath {
            let testPath = (bundlePath as NSString).appendingPathComponent("Resources/realesrgan-ncnn-vulkan")
            debugOutput += "Testing path: \(testPath)\n"
            if FileManager.default.fileExists(atPath: testPath) {
                executablePath = testPath
                debugOutput += "Method 3 success: Found at \(testPath)\n"
            } else {
                debugOutput += "File does not exist at \(testPath)\n"
            }

            let testModelsPath = (bundlePath as NSString).appendingPathComponent("Resources/models")
            if FileManager.default.fileExists(atPath: testModelsPath) {
                modelsPath = testModelsPath
                debugOutput += "Found models at: \(testModelsPath)\n"
            }
        }

        guard let executablePath = executablePath, let modelsPath = modelsPath else {
            debugOutput += "\nERROR: Binary or models not found in bundle\n"
            debugOutput += "The Resources folder needs to be added to the Xcode project's Copy Bundle Resources build phase\n"
            isProcessing = false
            return
        }

        debugOutput += "Executable: \(executablePath)\n"
        debugOutput += "Models path: \(modelsPath)\n"

        // Configure the process up front so cancellation can find it the moment
        // the user clicks Cancel, even if .run() hasn't been called yet.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        let arguments = [
            "-i", inputPath.path,
            "-o", outputPath.path,
            "-n", "realesrgan-x4plus",
            "-s", "4",
            "-m", modelsPath
        ]
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        upscaleProcess = process
        debugOutput += "Command: \(executablePath) \(arguments.joined(separator: " "))\n\n"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()

                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                outputHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.debugOutput += output
                            if let pct = Self.parseLastPercentage(in: output) {
                                self.upscaleProgress = pct / 100.0
                            }
                        }
                    }
                }

                errorHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.debugOutput += output
                            if let pct = Self.parseLastPercentage(in: output) {
                                self.upscaleProgress = pct / 100.0
                            }
                        }
                    }
                }

                process.waitUntilExit()

                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.upscaleProcess = nil
                    self.debugOutput += "\nProcess exited with status: \(process.terminationStatus)\n"

                    if self.upscaleCancelled {
                        self.debugOutput += "Upscaling cancelled by user.\n"
                    } else if process.terminationStatus == 0 {
                        if FileManager.default.fileExists(atPath: outputPath.path) {
                            if let upscaledImage = NSImage(contentsOf: outputPath) {
                                self.debugOutput += "SUCCESS: Loaded upscaled image\n"
                                self.debugOutput += "Original size: \(Int(originalImage.size.width))x\(Int(originalImage.size.height))\n"
                                self.debugOutput += "Upscaled size: \(Int(upscaledImage.size.width))x\(Int(upscaledImage.size.height))\n"
                                self.upscaledImages[targetURL] = upscaledImage
                                self.upscaleProgress = 1.0
                                self.updateDisplayImage()
                            } else {
                                self.debugOutput += "ERROR: Failed to load output image from \(outputPath.path)\n"
                            }
                        } else {
                            self.debugOutput += "ERROR: Output file not created at \(outputPath.path)\n"
                        }
                    } else {
                        self.debugOutput += "ERROR: Upscaling failed\n"
                    }

                    // Cleanup temp files
                    try? FileManager.default.removeItem(at: inputPath)
                    try? FileManager.default.removeItem(at: outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.upscaleProcess = nil
                    self.debugOutput += "ERROR running upscaling process: \(error)\n"
                    try? FileManager.default.removeItem(at: inputPath)
                    try? FileManager.default.removeItem(at: outputPath)
                }
            }
        }
    }

    private func cancelUpscale() {
        upscaleCancelled = true
        upscaleProcess?.terminate()
    }

    /// Scans `text` for the last "DDD.DD%" token and returns its numeric value
    /// (without the % sign). Used to drive the upscale progress bar from the
    /// realesrgan-ncnn-vulkan binary's stderr stream.
    static func parseLastPercentage(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)%"#) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard let last = matches.last else { return nil }
        return Double(nsText.substring(with: last.range(at: 1)))
    }

    private func invalidateUpscaling(for url: URL) {
        upscaledImages[url] = nil
    }

    private func removeUpscaling() {
        guard let url = imageLoader.currentImageURL else { return }
        upscaledImages[url] = nil
        updateDisplayImage()
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

        let alert = NSAlert()
        alert.messageText = "Rename Image"
        alert.informativeText = "Enter a new name for \"\(url.lastPathComponent)\":"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = basename
        alert.accessoryView = textField

        guard let window = myWindow ?? NSApplication.shared.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }

            let newURL = url.deletingLastPathComponent().appendingPathComponent("\(newName).\(ext)")
            guard newURL != url else { return }

            do {
                try FileManager.default.moveItem(at: url, to: newURL)

                if let val = self.rotationAngles.removeValue(forKey: url) { self.rotationAngles[newURL] = val }
                if let val = self.enhancedImages.removeValue(forKey: url) { self.enhancedImages[newURL] = val }
                if let val = self.smoothedImages.removeValue(forKey: url) { self.smoothedImages[newURL] = val }
                if let val = self.upscaledImages.removeValue(forKey: url) { self.upscaledImages[newURL] = val }
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
                self.windowTitle = newURL.lastPathComponent

                let message = "Renamed to \"\(newURL.lastPathComponent)\""
                self.savedToast = message
                self.savedToastIsError = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.savedToast == message { self.savedToast = nil }
                }
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
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        self.rotationAngles[url] = nil
                        self.enhancedImages[url] = nil
                        self.smoothedImages[url] = nil
                        self.upscaledImages[url] = nil
                        self.savedZoomScales[url] = nil
                        self.savedPanOffsets[url] = nil
                        self.infoOverlayURLs.remove(url)
                        self.imageInfoCache[url] = nil
                        self.imageLoader.removeImage(at: url)
                    } catch {
                        self.showErrorToast("Failed to trash: \(error.localizedDescription)")
                    }
                }
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
    }

    private func saveFavourites() {
        UserDefaults.standard.set(Array(favouriteURLStrings), forKey: "favouriteImages")
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
        .task(id: url) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.get(url) {
            self.thumbnail = cached
            return
        }
        let maxPixel = Int(size * 2) // 2x for retina
        let target = url
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
            .onChange(of: imageLoader.currentIndex) { _, _ in
                if let url = imageLoader.currentImageURL {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let url = imageLoader.currentImageURL {
                    proxy.scrollTo(url, anchor: .center)
                }
            }
        }
    }
}

#Preview {
    SlideshowView()
        .environmentObject(RecentDirectories())
}
