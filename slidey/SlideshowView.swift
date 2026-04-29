import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers

enum PanDirection {
    case left, right, up, down
}

/// Routes mouse clicks, trackpad pinch, and scroll-wheel events to separate
/// callbacks. Implemented as a single NSView so events aren't raced between
/// the SwiftUI gesture system and an AppKit overlay.
struct ClickCatcher: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    /// Multiplier (e.g. 1.05 means zoom in by 5%).
    let onZoom: (CGFloat) -> Void
    /// Pan deltas in points; sign matches NSEvent.scrollingDeltaX/Y.
    let onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onZoom = onZoom
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onZoom = onZoom
        nsView.onScroll = onScroll
    }
}

class ClickCatcherView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Treat ctrl+left-click as right-click, matching AppKit menu conventions.
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func magnify(with event: NSEvent) {
        // event.magnification is a per-tick delta multiplier (e.g. 0.05 ≈ +5%).
        onZoom?(1.0 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Cmd+scroll → zoom. 0.005 makes a typical wheel click ~5%.
            onZoom?(1.0 + event.scrollingDeltaY * 0.005)
        } else {
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }

    // Receive clicks even when the window isn't yet key, so the first click
    // navigates instead of just activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Stay out of the responder chain so the parent SwiftUI view keeps
    // receiving key presses.
    override var acceptsFirstResponder: Bool { false }
}

struct SlideshowView: View {
    @StateObject private var imageLoader = ImageLoader()
    @EnvironmentObject var recentDirectories: RecentDirectories
    @EnvironmentObject var pendingOpens: PendingOpens
    @State private var selectedDirectory: URL?
    @State private var scopedDirectory: URL?
    @State private var isFullScreen = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var windowSize: CGSize = .zero
    @State private var rotationAngle: Angle = .zero
    @State private var rotationAngles: [URL: Angle] = [:]
    @State private var lastDisplayedURL: URL?
    @State private var windowTitle: String = "Slidey"
    @State private var enhancedImages: [URL: NSImage] = [:]
    @State private var smoothedImages: [URL: NSImage] = [:]
    @State private var upscaledImages: [URL: NSImage] = [:]
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
    @State private var isPlaying = false
    @State private var slideshowTimer: Timer?
    @State private var savedToast: String?
    @State private var savedToastIsError: Bool = false
    @State private var showThumbnails = false
    @AppStorage("slideshowInterval") private var slideshowInterval: Double = 5
    @AppStorage("sortOrder") private var sortOrder: AppSortOrder = .creationDateAscending

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if imageLoader.imageURLs.isEmpty {
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
            } else {
                GeometryReader { geometry in
                    if let image = currentDisplayImage {
                        ImageDisplayView(
                            image: image,
                            zoomScale: $zoomScale,
                            imageOffset: $imageOffset,
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
                        .onAppear {
                            windowSize = geometry.size
                            updateDisplayImage()
                            captureWindow()
                        }
                        .onChange(of: geometry.size) { oldSize, newSize in
                            windowSize = newSize
                        }
                    }
                }
            }

            // Thumbnail strip overlay (bottom)
            if showThumbnails && !imageLoader.imageURLs.isEmpty {
                VStack {
                    Spacer()
                    ThumbnailStrip(imageLoader: imageLoader) { index in
                        guard !isProcessing else { return }
                        imageLoader.jumpTo(index: index)
                    }
                }
            }

            // Filename + counter overlay
            if showFilename, let filename = imageLoader.currentImageURL?.lastPathComponent {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 12) {
                            Text(filename)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                            Text("\(imageLoader.currentIndex + 1) / \(imageLoader.imageURLs.count)")
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
                rotationAngle = currentURLRotation()
                updateDisplayImage()
                enterFullScreen()
            } else {
                stopSlideshow()
            }
            updateCursorVisibility()
        }
        .onChange(of: imageLoader.imageURLs) { _, newURLs in
            // Drop any per-URL session state for files that no longer exist
            // in the directory (deleted on disk, or we switched folders).
            let valid = Set(newURLs)
            rotationAngles = rotationAngles.filter { valid.contains($0.key) }
            enhancedImages = enhancedImages.filter { valid.contains($0.key) }
            smoothedImages = smoothedImages.filter { valid.contains($0.key) }
            upscaledImages = upscaledImages.filter { valid.contains($0.key) }

            rotationAngle = currentURLRotation()
            if !newURLs.isEmpty {
                updateDisplayImage()
            }
        }
        .onChange(of: imageLoader.currentIndex) { _, _ in
            // Only reset zoom/pan when the displayed *file* changes. A rescan
            // can shift currentIndex while keeping the same file under the
            // cursor; that shouldn't yank the user out of their zoom.
            let newURL = imageLoader.currentImageURL
            if newURL != lastDisplayedURL {
                resetZoomAndPan()
                lastDisplayedURL = newURL
            }
            rotationAngle = currentURLRotation()
            updateDisplayImage()
            // Reset the auto-advance clock on every navigation (manual or
            // auto) so the next tick is always `interval` from now.
            if isPlaying { rescheduleSlideshowTimer() }
        }
        .onChange(of: isFullScreen) { _, _ in
            updateCursorVisibility()
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
            consumePendingOpenIfPossible()
        }
        .onDisappear {
            stopSlideshow()
        }
        .onChange(of: pendingOpens.pending) { _, _ in
            consumePendingOpenIfPossible()
        }
        .onChange(of: isProcessing) { _, isP in
            if isP {
                stopSlideshow()
            } else {
                consumePendingOpenIfPossible()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectDirectory"))) { _ in
            ifKeyWindow { selectDirectory() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenDirectory"))) { notification in
            if let entry = notification.object as? RecentDirectory {
                ifKeyWindow { openRecent(entry) }
            }
        }
        .onChange(of: windowTitle) { _, newTitle in
            updateWindowTitle(newTitle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EnhanceImage"))) { _ in
            ifKeyWindow { enhanceCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveEnhancement"))) { _ in
            ifKeyWindow { removeEnhancement() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScaleToNative"))) { _ in
            ifKeyWindow { zoomToNativeSize() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScaleToFill"))) { _ in
            ifKeyWindow { zoomToFillScreen() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RotateClockwise"))) { _ in
            ifKeyWindow { rotateClockwise() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RotateCounterClockwise"))) { _ in
            ifKeyWindow { rotateCounterClockwise() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SmoothImage"))) { _ in
            ifKeyWindow { smoothCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveSmoothing"))) { _ in
            ifKeyWindow { removeSmoothing() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UpscaleImage"))) { _ in
            ifKeyWindow { upscaleCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveUpscaling"))) { _ in
            ifKeyWindow { removeUpscaling() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SaveEditedImage"))) { _ in
            ifKeyWindow { saveEditedImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSlideshow"))) { _ in
            // Allow toggle even mid-upscale: pause is always safe; play is
            // gated inside startSlideshow on isProcessing.
            if myWindow == nil || myWindow?.isKeyWindow == true {
                toggleSlideshow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleThumbnails"))) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                showThumbnails.toggle()
            }
        }
        .onChange(of: slideshowInterval) { _, _ in
            if isPlaying { rescheduleSlideshowTimer() }
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

    private func canPan(direction: PanDirection) -> Bool {
        guard zoomScale > 1.0,
              let image = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let fitScale = min(windowSize.width / imageSize.width, windowSize.height / imageSize.height)
        let displayedSize = CGSize(
            width: imageSize.width * fitScale * zoomScale,
            height: imageSize.height * fitScale * zoomScale
        )

        let maxOffsetX = max(0, (displayedSize.width - windowSize.width) / 2)
        let maxOffsetY = max(0, (displayedSize.height - windowSize.height) / 2)

        switch direction {
        case .left:
            return imageOffset.width < maxOffsetX - 10
        case .right:
            return imageOffset.width > -maxOffsetX + 10
        case .up:
            return imageOffset.height < maxOffsetY - 10
        case .down:
            return imageOffset.height > -maxOffsetY + 10
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

        if zoomScale > 1.0 {
            switch key {
            case .leftArrow:
                if canPan(direction: .left) {
                    imageOffset.width += 50
                } else {
                    imageLoader.previousImage()
                }
                return .handled
            case .rightArrow:
                if canPan(direction: .right) {
                    imageOffset.width -= 50
                } else {
                    imageLoader.nextImage()
                }
                return .handled
            case .upArrow:
                if canPan(direction: .up) {
                    imageOffset.height += 50
                } else {
                    // Optional: could navigate images here too
                }
                return .handled
            case .downArrow:
                if canPan(direction: .down) {
                    imageOffset.height -= 50
                } else {
                    // Optional: could navigate images here too
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
            zoomScale = min(zoomScale * 1.2, 10.0)
            return .handled
        case "-", "_":
            zoomScale = max(zoomScale / 1.2, 0.1)
            if zoomScale <= 1.0 {
                resetZoomAndPan()
            }
            return .handled
        case "s", "S":
            // Let cmd+s flow through to the File > Save Edited Image menu
            // shortcut instead of being absorbed by the native-zoom handler.
            guard !keyPress.modifiers.contains(.command) else { return .ignored }
            zoomToNativeSize()
            return .handled
        case "f", "F":
            zoomToFillScreen()
            return .handled
        case "r":
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
        case "n":
            showFilename.toggle()
            return .handled
        case "d":
            showDebugWindow.toggle()
            return .handled
        case "t":
            showThumbnails.toggle()
            return .handled
        case " ":
            toggleSlideshow()
            return .handled
        default:
            if zoomScale <= 1.0 {
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
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false

            // Show panel as a sheet on this view's window (or the key window if we haven't captured it yet)
            if let window = self.myWindow ?? NSApplication.shared.keyWindow {
                panel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = panel.url {
                        self.openDirectory(url: url)
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

    private func openDirectory(url: URL, isScoped: Bool = false) {
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
        resetZoomAndPan()

        imageLoader.loadImagesFromDirectory(url: url)
        windowTitle = url.lastPathComponent
        // updateDisplayImage will be called by onChange(of: imageLoader.imageURLs)
    }

    private func toggleSlideshow() {
        if isPlaying { stopSlideshow() } else { startSlideshow() }
    }

    private func startSlideshow() {
        guard !isProcessing,
              !imageLoader.imageURLs.isEmpty,
              imageLoader.imageURLs.count > 1 else { return }
        isPlaying = true
        rescheduleSlideshowTimer()
    }

    private func stopSlideshow() {
        isPlaying = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }

    private func rescheduleSlideshowTimer() {
        slideshowTimer?.invalidate()
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { _ in
            imageLoader.nextImage()
        }
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

    private func resetZoomAndPan() {
        zoomScale = 1.0
        imageOffset = .zero
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
    private static func parseLastPercentage(in text: String) -> Double? {
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

    private func zoomToNativeSize() {
        guard let image = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Calculate how much .scaledToFit() scales the image
        let fitScale = min(windowSize.width / imageSize.width, windowSize.height / imageSize.height)

        // Zoom to counteract the fit scaling to show native size
        zoomScale = 1.0 / fitScale
        imageOffset = .zero
    }

    private func zoomToFillScreen() {
        guard let image = currentDisplayImage ?? imageLoader.currentImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Determine if image is portrait or landscape
        let isPortrait = imageSize.height > imageSize.width

        // Calculate how much .scaledToFit() scales the image
        let fitScale = min(windowSize.width / imageSize.width, windowSize.height / imageSize.height)

        // Fill based on orientation
        let fillScale: CGFloat
        if isPortrait {
            // Portrait: fill height
            fillScale = windowSize.height / imageSize.height
        } else {
            // Landscape: fill width
            fillScale = windowSize.width / imageSize.width
        }

        // Zoom to fill
        zoomScale = fillScale / fitScale
        imageOffset = .zero
    }
}

struct ImageDisplayView: View {
    let image: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var imageOffset: CGSize
    let containerSize: CGSize
    @Binding var rotationAngle: Angle
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    @AppStorage("naturalScrollPan") private var naturalScrollPan: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(rotationAngle)
                    .scaleEffect(zoomScale)
                    .offset(imageOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ClickCatcher(
                    onLeftClick: onLeftClick,
                    onRightClick: onRightClick,
                    onZoom: { factor in applyZoom(factor) },
                    onScroll: { dx, dy in applyPan(dx: dx, dy: dy) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        let oldScale = zoomScale
        let newScale = max(0.1, min(10.0, oldScale * factor))
        if newScale == oldScale { return }
        // Scale the existing offset so the same image point stays under the
        // view center as we zoom in or out.
        let actual = newScale / oldScale
        zoomScale = newScale
        imageOffset = CGSize(
            width: imageOffset.width * actual,
            height: imageOffset.height * actual
        )
        clampOffset()
    }

    private func applyPan(dx: CGFloat, dy: CGFloat) {
        let bounds = panBounds()
        // Don't pan when the image fits the container — there's nowhere to go,
        // and we don't want plain trackpad scroll to do anything in fit-mode.
        guard bounds.x > 0 || bounds.y > 0 else { return }
        let sign: CGFloat = naturalScrollPan ? 1 : -1
        imageOffset.width += sign * dx
        imageOffset.height -= sign * dy
        clampOffset()
    }

    private func clampOffset() {
        let bounds = panBounds()
        imageOffset.width = max(-bounds.x, min(bounds.x, imageOffset.width))
        imageOffset.height = max(-bounds.y, min(bounds.y, imageOffset.height))
    }

    private func panBounds() -> (x: CGFloat, y: CGFloat) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (0, 0)
        }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let fitScale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let displayed = CGSize(
            width: imageSize.width * fitScale * zoomScale,
            height: imageSize.height * fitScale * zoomScale
        )
        return (
            x: max(0, (displayed.width - containerSize.width) / 2),
            y: max(0, (displayed.height - containerSize.height) / 2)
        )
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        // Hold up to 500 thumbnails; NSCache also evicts under memory pressure.
        cache.countLimit = 500
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
