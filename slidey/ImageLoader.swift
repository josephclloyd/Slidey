import Foundation
import AppKit

class ImageLoader: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var currentIndex: Int = 0

    private let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]

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

        // Sort by creation date
        fileURLs.sort { $0.1 < $1.1 }

        // Load images in sorted order
        var loadedImages: [NSImage] = []
        for (fileURL, _) in fileURLs {
            if let image = NSImage(contentsOf: fileURL) {
                loadedImages.append(image)
            }
        }

        DispatchQueue.main.async {
            self.images = loadedImages
            self.currentIndex = loadedImages.isEmpty ? 0 : 0
        }
    }

    func nextImage() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex + 1) % images.count
    }

    func previousImage() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex - 1 + images.count) % images.count
    }

    var currentImage: NSImage? {
        guard !images.isEmpty && currentIndex < images.count else { return nil }
        return images[currentIndex]
    }
}
