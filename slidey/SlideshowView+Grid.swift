import SwiftUI

// Grid / contact-sheet view: shows every image in the active (filtered) set at
// once as a scrollable thumbnail grid. Toggled with Shift-T. Selecting a
// thumbnail (click or arrow-keys + Return) jumps to that image and exits.
extension SlideshowView {
    @ViewBuilder
    var gridOverlay: some View {
        if showGridView {
            GridContactSheet(
                imageLoader: imageLoader,
                favouriteURLStrings: favouriteURLStrings,
                selection: gridSelection,
                columnCount: $gridColumnCount,
                onSelect: { index in selectGridImage(at: index) }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }

    func toggleGridView() {
        if showGridView {
            showGridView = false
        } else {
            guard !imageLoader.imageURLs.isEmpty else { return }
            gridSelection = imageLoader.currentIndex
            showGridView = true
        }
    }

    func selectGridImage(at index: Int) {
        guard imageLoader.imageURLs.indices.contains(index) else { return }
        imageLoader.jumpTo(index: index)
        showGridView = false
    }

    func handleGridKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let count = imageLoader.imageURLs.count
        if keyPress.key == .escape || keyPress.characters == "T" {
            showGridView = false
            return .handled
        }
        guard count > 0 else { return .handled }
        if keyPress.characters == "\r" {
            selectGridImage(at: gridSelection)
            return .handled
        }
        let columns = max(1, gridColumnCount)
        switch keyPress.key {
        case .leftArrow:
            gridSelection = max(0, gridSelection - 1)
        case .rightArrow:
            gridSelection = min(count - 1, gridSelection + 1)
        case .upArrow:
            gridSelection = max(0, gridSelection - columns)
        case .downArrow:
            gridSelection = min(count - 1, gridSelection + columns)
        default:
            break
        }
        // Swallow all keys while the grid is open so navigation and edit
        // shortcuts can't fire on the hidden image underneath.
        return .handled
    }
}

struct GridContactSheet: View {
    @ObservedObject var imageLoader: ImageLoader
    var favouriteURLStrings: Set<String> = []
    let selection: Int
    @Binding var columnCount: Int
    let onSelect: (Int) -> Void

    private let thumbSize: CGFloat = 140
    private let spacing: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize), spacing: spacing)]
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(imageLoader.imageURLs.enumerated()), id: \.element) { pair in
                            ThumbnailCell(
                                url: pair.element,
                                size: thumbSize,
                                isSelected: pair.offset == selection,
                                isFavourite: favouriteURLStrings.contains(pair.element.absoluteString),
                                onTap: { onSelect(pair.offset) }
                            )
                            .id(pair.offset)
                        }
                    }
                    .padding(spacing)
                }
                .onAppear {
                    updateColumnCount(width: geo.size.width)
                    DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
                }
                .onChange(of: geo.size.width) { _, width in updateColumnCount(width: width) }
                .onChange(of: selection) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .background(.black.opacity(0.92))
        .accessibilityLabel("Grid view, \(imageLoader.imageURLs.count) images")
    }

    private func updateColumnCount(width: CGFloat) {
        guard width > 0 else { return }
        let count = max(1, Int((width - spacing) / (thumbSize + spacing)))
        if count != columnCount { columnCount = count }
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
