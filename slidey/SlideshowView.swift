import SwiftUI
import AppKit
import CoreImage

enum PanDirection {
    case left, right, up, down
}

// View modifier for handling right-click
struct RightClickModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(
                RightClickHandler(action: action)
                    .allowsHitTesting(true)
            )
    }
}

struct RightClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickView()
        view.onRightClick = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? RightClickView {
            view.onRightClick = action
        }
    }
}

class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Make sure we can receive mouse events
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        self.modifier(RightClickModifier(action: action))
    }
}

struct SlideshowView: View {
    @StateObject private var imageLoader = ImageLoader()
    @EnvironmentObject var recentDirectories: RecentDirectories
    @State private var selectedDirectory: URL?
    @State private var scopedDirectory: URL?
    @State private var isFullScreen = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var windowSize: CGSize = .zero
    @State private var rotationAngle: Angle = .zero
    @State private var rotationAngles: [Int: Angle] = [:]
    @State private var windowTitle: String = "Slidey"
    @State private var enhancedImages: [Int: NSImage] = [:]
    @State private var smoothedImages: [Int: NSImage] = [:]
    @State private var upscaledImages: [Int: NSImage] = [:]
    @State private var currentDisplayImage: NSImage?
    @State private var myWindow: NSWindow?
    @State private var windowHasFocus = false
    @State private var isProcessing = false
    @State private var debugOutput = ""
    @State private var showDebugWindow = false
    @State private var showFilename = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if imageLoader.images.isEmpty {
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
                    setupWindowObservers()
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
                                imageLoader.nextImage()
                            },
                            onRightClick: {
                                imageLoader.previousImage()
                            }
                        )
                        .onAppear {
                            windowSize = geometry.size
                            updateDisplayImage()
                            captureWindow()
                            setupWindowObservers()
                        }
                        .onChange(of: geometry.size) { oldSize, newSize in
                            windowSize = newSize
                        }
                    }
                }
            }

            // Filename overlay
            if showFilename, let filename = imageLoader.currentImageURL?.lastPathComponent {
                VStack {
                    Spacer()
                    HStack {
                        Text(filename)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
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

            // Progress indicator overlay
            if isProcessing {
                VStack {
                    Spacer()
                    VStack(spacing: 15) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("AI Upscaling Image (4x)...")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("This may take 10-30 seconds")
                            .font(.subheadline)
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
        .onChange(of: imageLoader.images.isEmpty) { _, isEmpty in
            if !isEmpty {
                rotationAngles = [:]
                rotationAngle = .zero
                enhancedImages = [:]
                smoothedImages = [:]
                upscaledImages = [:]
                loadRotationForImage(at: imageLoader.currentIndex)
                updateDisplayImage()
                enterFullScreen()
            }
            updateCursorVisibility()
        }
        .onChange(of: imageLoader.images) { oldImages, newImages in
            // When images change, update the display
            if !newImages.isEmpty {
                updateDisplayImage()
            }
        }
        .onChange(of: imageLoader.currentIndex) { oldIndex, newIndex in
            saveRotationForImage(at: oldIndex)
            loadRotationForImage(at: newIndex)
            resetZoomAndPan()
            updateDisplayImage()
        }
        .onChange(of: isFullScreen) { _, _ in
            updateCursorVisibility()
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectDirectory"))) { _ in
            // Only respond if this view's window is the key window (or if we haven't captured a window yet)
            if myWindow == nil || myWindow?.isKeyWindow == true {
                selectDirectory()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenDirectory"))) { notification in
            // Only respond if this view's window is the key window (or if we haven't captured a window yet)
            if let entry = notification.object as? RecentDirectory {
                if myWindow == nil || myWindow?.isKeyWindow == true {
                    openRecent(entry)
                }
            }
        }
        .onChange(of: windowTitle) { _, newTitle in
            updateWindowTitle(newTitle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EnhanceImage"))) { _ in
            enhanceCurrentImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveEnhancement"))) { _ in
            removeEnhancement()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScaleToNative"))) { _ in
            zoomToNativeSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScaleToFill"))) { _ in
            zoomToFillScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RotateClockwise"))) { _ in
            rotateClockwise()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RotateCounterClockwise"))) { _ in
            rotateCounterClockwise()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SmoothImage"))) { _ in
            smoothCurrentImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveSmoothing"))) { _ in
            removeSmoothing()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UpscaleImage"))) { _ in
            upscaleCurrentImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RemoveUpscaling"))) { _ in
            removeUpscaling()
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
            toggleFullScreen()
            return .handled
        }

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
    }

    private func setupWindowObservers() {
        // Observe when window becomes key (gains focus)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = true
                updateCursorVisibility()
            }
        }

        // Observe when window resigns key (loses focus)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = false
                updateCursorVisibility()
            }
        }

        // Set initial focus state
        if let myWindow = myWindow {
            windowHasFocus = myWindow.isKeyWindow
            updateCursorVisibility()
        }
    }

    private func updateCursorVisibility() {
        // Hide cursor only if: images are loaded AND fullscreen AND window has focus
        let shouldHideCursor = !imageLoader.images.isEmpty && isFullScreen && windowHasFocus

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
        // updateDisplayImage will be called by onChange(of: imageLoader.images)
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

    private func saveRotationForImage(at index: Int) {
        rotationAngles[index] = rotationAngle
    }

    private func loadRotationForImage(at index: Int) {
        rotationAngle = rotationAngles[index] ?? .zero
    }

    private func rotateClockwise() {
        rotationAngle = Angle(degrees: rotationAngle.degrees + 90)
    }

    private func rotateCounterClockwise() {
        rotationAngle = Angle(degrees: rotationAngle.degrees - 90)
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
        let index = imageLoader.currentIndex
        // Priority: upscaled > smoothed > enhanced > original
        if let upscaled = upscaledImages[index] {
            currentDisplayImage = upscaled
        } else if let smoothed = smoothedImages[index] {
            currentDisplayImage = smoothed
        } else if let enhanced = enhancedImages[index] {
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
            let index = imageLoader.currentIndex
            enhancedImages[index] = enhancedNSImage
            invalidateUpscaling(for: index)
            currentDisplayImage = enhancedNSImage
        }
    }

    private func removeEnhancement() {
        let index = imageLoader.currentIndex
        enhancedImages[index] = nil
        invalidateUpscaling(for: index)
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
            let index = imageLoader.currentIndex
            smoothedImages[index] = smoothedNSImage
            invalidateUpscaling(for: index)
            currentDisplayImage = smoothedNSImage
        }
    }

    private func removeSmoothing() {
        let index = imageLoader.currentIndex
        smoothedImages[index] = nil
        invalidateUpscaling(for: index)
        updateDisplayImage()
    }

    private func upscaleCurrentImage() {
        guard !isProcessing else { return }
        let index = imageLoader.currentIndex
        // Upscale the best non-upscaled version: smoothed > enhanced > original
        guard let sourceImage = smoothedImages[index] ?? enhancedImages[index] ?? imageLoader.currentImage else { return }

        isProcessing = true
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

        // Run upscaling in background
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "-i", inputPath.path,
                "-o", outputPath.path,
                "-n", "realesrgan-x4plus",
                "-s", "4",
                "-m", modelsPath
            ]

            // Capture stdout and stderr
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            DispatchQueue.main.async {
                self.debugOutput += "Command: \(executablePath) \(process.arguments!.joined(separator: " "))\n\n"
            }

            do {
                try process.run()

                // Read output asynchronously
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                outputHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.debugOutput += output
                        }
                    }
                }

                errorHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.debugOutput += output
                        }
                    }
                }

                process.waitUntilExit()

                // Stop reading
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.debugOutput += "\nProcess exited with status: \(process.terminationStatus)\n"

                    if process.terminationStatus == 0 {
                        if FileManager.default.fileExists(atPath: outputPath.path) {
                            let index = self.imageLoader.currentIndex
                            if let upscaledImage = NSImage(contentsOf: outputPath) {
                                self.debugOutput += "SUCCESS: Loaded upscaled image\n"
                                self.debugOutput += "Original size: \(Int(originalImage.size.width))x\(Int(originalImage.size.height))\n"
                                self.debugOutput += "Upscaled size: \(Int(upscaledImage.size.width))x\(Int(upscaledImage.size.height))\n"
                                self.upscaledImages[index] = upscaledImage
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
                    self.debugOutput += "ERROR running upscaling process: \(error)\n"
                    try? FileManager.default.removeItem(at: inputPath)
                    try? FileManager.default.removeItem(at: outputPath)
                }
            }
        }
    }

    private func invalidateUpscaling(for index: Int) {
        upscaledImages[index] = nil
    }

    private func removeUpscaling() {
        upscaledImages[imageLoader.currentIndex] = nil
        updateDisplayImage()
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

                // Transparent overlay to capture clicks
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        onLeftClick()
                    }
                    .onRightClick {
                        onRightClick()
                    }
            }
        }
    }
}

#Preview {
    SlideshowView()
        .environmentObject(RecentDirectories())
}
