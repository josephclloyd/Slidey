import SwiftUI
import AppKit
import CoreImage

struct SlideshowView: View {
    @StateObject private var imageLoader = ImageLoader()
    @EnvironmentObject var recentDirectories: RecentDirectories
    @State private var selectedDirectory: URL?
    @State private var isFullScreen = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var windowSize: CGSize = .zero
    @State private var rotationAngle: Angle = .zero
    @State private var rotationAngles: [Int: Angle] = [:]
    @State private var windowTitle: String = "Slidey"
    @State private var enhancedImages: [Int: NSImage] = [:]
    @State private var smoothedImages: [Int: NSImage] = [:]
    @State private var currentDisplayImage: NSImage?

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
                                    ForEach(recentDirectories.directories, id: \.self) { url in
                                        Button(action: {
                                            openDirectory(url: url)
                                        }) {
                                            HStack {
                                                Image(systemName: "folder.fill")
                                                    .foregroundColor(.blue)
                                                Text(url.lastPathComponent)
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
            } else {
                GeometryReader { geometry in
                    if let image = currentDisplayImage {
                        ImageDisplayView(
                            image: image,
                            zoomScale: $zoomScale,
                            imageOffset: $imageOffset,
                            containerSize: geometry.size,
                            rotationAngle: $rotationAngle
                        )
                        .onAppear {
                            windowSize = geometry.size
                            updateDisplayImage()
                        }
                        .onChange(of: geometry.size) { oldSize, newSize in
                            windowSize = newSize
                        }
                    }
                }
            }
        }
        .onChange(of: imageLoader.images.isEmpty) { _, isEmpty in
            if !isEmpty {
                rotationAngles = [:]
                rotationAngle = .zero
                enhancedImages = [:]
                smoothedImages = [:]
                updateDisplayImage()
                NSCursor.hide()
                enterFullScreen()
            } else {
                NSCursor.unhide()
            }
        }
        .onChange(of: imageLoader.currentIndex) { oldIndex, newIndex in
            saveRotationForImage(at: oldIndex)
            loadRotationForImage(at: newIndex)
            resetZoomAndPan()
            updateDisplayImage()
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectDirectory"))) { _ in
            selectDirectory()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenDirectory"))) { notification in
            if let url = notification.object as? URL {
                openDirectory(url: url)
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
                imageOffset.width += 50
                return .handled
            case .rightArrow:
                imageOffset.width -= 50
                return .handled
            case .upArrow:
                imageOffset.height += 50
                return .handled
            case .downArrow:
                imageOffset.height -= 50
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
        default:
            if zoomScale <= 1.0 {
                imageLoader.nextImage()
                return .handled
            }
        }

        return .ignored
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openDirectory(url: url)
        }
    }

    private func openDirectory(url: URL) {
        selectedDirectory = url
        recentDirectories.addDirectory(url)
        imageLoader.loadImagesFromDirectory(url: url)
        windowTitle = url.lastPathComponent
        enterFullScreen()
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

            // Show cursor when exiting fullscreen
            if !isFullScreen {
                NSCursor.unhide()
            } else {
                NSCursor.hide()
            }
        }
    }

    private func exitFullScreen() {
        if let window = NSApplication.shared.keyWindow {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                isFullScreen = false
                NSCursor.unhide()
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
        if let smoothed = smoothedImages[index] {
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
            enhancedImages[imageLoader.currentIndex] = enhancedNSImage
            currentDisplayImage = enhancedNSImage
        }
    }

    private func removeEnhancement() {
        enhancedImages[imageLoader.currentIndex] = nil
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
            smoothedImages[imageLoader.currentIndex] = smoothedNSImage
            currentDisplayImage = smoothedNSImage
        }
    }

    private func removeSmoothing() {
        smoothedImages[imageLoader.currentIndex] = nil
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

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .rotationEffect(rotationAngle)
                .scaleEffect(zoomScale)
                .offset(imageOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SlideshowView()
        .environmentObject(RecentDirectories())
}
