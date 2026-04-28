import Foundation
import AppKit
import ImageIO

class ImageLoader: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var currentIndex: Int = 0
    @Published var currentImage: NSImage?

    private let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]

    /// Maximum decoded pixel count we will accept. Guards against
    /// decompression bombs - small files that decode to enormous bitmaps and
    /// exhaust memory. 200 megapixels is generous (a 50 MP camera frame
    /// upscaled 4x is ~200 MP) but still bounded.
    private let maxPixelCount = 200_000_000

    /// Number of neighbours on each side of the current image to keep decoded
    /// in memory. Bounds resident memory regardless of folder size.
    private let cacheRadius = 1

    private var cache: [Int: NSImage] = [:]

    var currentImageURL: URL? {
        guard !imageURLs.isEmpty && currentIndex < imageURLs.count else { return nil }
        return imageURLs[currentIndex]
    }

    func loadImagesFromDirectory(url: URL) {
        var fileURLs: [(URL, Date)] = []

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) {
                let creationDate = resourceValues.creationDate ?? Date.distantPast
                fileURLs.append((fileURL, creationDate))
            }
        }

        fileURLs.sort { $0.1 < $1.1 }
        let urls = fileURLs.map { $0.0 }

        DispatchQueue.main.async {
            self.cache.removeAll()
            self.imageURLs = urls
            self.currentIndex = 0
            self.currentImage = self.loadImage(at: 0)
            self.preloadNeighbours()
        }
    }

    func nextImage() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % imageURLs.count
        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    func previousImage() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    private func loadImage(at index: Int) -> NSImage? {
        guard imageURLs.indices.contains(index) else { return nil }
        if let cached = cache[index] {
            return cached
        }
        guard let image = decodeBoundedImage(at: imageURLs[index]) else {
            return nil
        }
        cache[index] = image
        evictDistantCache()
        return image
    }

    /// Inspects the image's pixel dimensions before fully decoding it. Files
    /// that decode to more than `maxPixelCount` pixels are rejected so a
    /// crafted small file can't allocate a multi-gigabyte bitmap.
    private func decodeBoundedImage(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        if width <= 0 || height <= 0 { return nil }
        if width.multipliedReportingOverflow(by: height).overflow { return nil }
        if width * height > maxPixelCount { return nil }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func preloadNeighbours() {
        let count = imageURLs.count
        guard count > 1 else { return }
        let urlsSnapshot = imageURLs
        let center = currentIndex

        for offset in -cacheRadius...cacheRadius where offset != 0 {
            let i = (center + offset + count) % count
            if cache[i] != nil { continue }

            let neighbourURL = urlsSnapshot[i]
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                guard let img = self.decodeBoundedImage(at: neighbourURL) else { return }
                DispatchQueue.main.async {
                    // Drop the result if the directory changed underneath us.
                    guard self.imageURLs.indices.contains(i),
                          self.imageURLs[i] == neighbourURL else { return }
                    self.cache[i] = img
                    self.evictDistantCache()
                }
            }
        }
    }

    private func evictDistantCache() {
        let count = imageURLs.count
        guard count > 0 else { cache.removeAll(); return }
        var keep = Set<Int>()
        for offset in -cacheRadius...cacheRadius {
            keep.insert((currentIndex + offset + count) % count)
        }
        for k in cache.keys where !keep.contains(k) {
            cache.removeValue(forKey: k)
        }
    }
}
