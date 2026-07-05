import SwiftUI
import ImageIO

extension SlideshowView {

    func setRating(_ rating: Int) {
        guard let url = imageLoader.currentImageURL else { return }
        let clamped = max(0, min(5, rating))
        guard clamped != (imageRatings[url] ?? 0) else { return }
        let previous = imageRatings[url]

        if clamped == 0 {
            imageRatings.removeValue(forKey: url)
        } else {
            imageRatings[url] = clamped
        }

        if minimumRatingFilter > 0 { updateFilter() }

        let stars = clamped > 0
            ? String(repeating: "\u{2605}", count: clamped)
            : "Rating cleared"
        savedToast = stars
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == stars { self.savedToast = nil }
        }

        Task.detached(priority: .utility) {
            do {
                try writeRatingToFile(url: url, rating: clamped)
            } catch {
                await MainActor.run {
                    if let prev = previous {
                        self.imageRatings[url] = prev
                    } else {
                        self.imageRatings.removeValue(forKey: url)
                    }
                    self.savedToast = "Rating failed: \(error.localizedDescription)"
                    self.savedToastIsError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if self.savedToast?.starts(with: "Rating failed") == true {
                            self.savedToast = nil
                        }
                    }
                }
            }
        }
    }

    func loadRatingsForDirectory() {
        let urls = imageLoader.allImageURLs
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            let ratings = readAllRatings(for: urls)
            await MainActor.run {
                self.imageRatings = ratings
                if self.minimumRatingFilter > 0 { self.updateFilter() }
            }
        }
    }
}

private func readAllRatings(for urls: [URL]) -> [URL: Int] {
    var result: [URL: Int] = [:]
    for url in urls {
        if let r = readRatingFromFile(url), r > 0 {
            result[url] = r
        }
    }
    return result
}

func readRatingFromFile(_ url: URL) -> Int? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
        return nil
    }
    guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString),
          let value = CGImageMetadataTagCopyValue(tag) else {
        return nil
    }
    if let intVal = value as? Int { return intVal }
    if let strVal = value as? String { return Int(strVal) }
    if let numVal = value as? NSNumber { return numVal.intValue }
    return nil
}

func writeRatingToFile(url: URL, rating: Int) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let uti = CGImageSourceGetType(source) else {
        throw RatingError.cannotReadSource
    }

    let metadata: CGMutableImageMetadata
    if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
        guard let copy = CGImageMetadataCreateMutableCopy(existing) else {
            throw RatingError.cannotCreateMetadata
        }
        metadata = copy
    } else {
        metadata = CGImageMetadataCreateMutable()
    }

    CGImageMetadataRegisterNamespaceForPrefix(
        metadata,
        "http://ns.adobe.com/xap/1.0/" as CFString,
        "xmp" as CFString,
        nil
    )

    let success: Bool
    if rating == 0 {
        success = CGImageMetadataSetValueWithPath(
            metadata, nil, "xmp:Rating" as CFString, "0" as CFTypeRef
        )
    } else {
        success = CGImageMetadataSetValueWithPath(
            metadata, nil, "xmp:Rating" as CFString, "\(rating)" as CFTypeRef
        )
    }
    guard success else { throw RatingError.cannotSetTag }

    let tempURL = url.deletingLastPathComponent()
        .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)

    guard let destination = CGImageDestinationCreateWithURL(
        tempURL as CFURL, uti, 0, nil
    ) else {
        throw RatingError.cannotCreateDestination
    }

    var error: Unmanaged<CFError>?
    let options: [CFString: Any] = [
        kCGImageDestinationMetadata: metadata,
        kCGImageDestinationMergeMetadata: true,
    ]

    let copied = CGImageDestinationCopyImageSource(
        destination, source, options as CFDictionary, &error
    )

    if !copied {
        try? FileManager.default.removeItem(at: tempURL)
        if let cfError = error?.takeRetainedValue() {
            throw cfError as Error
        }
        throw RatingError.writeFailed
    }

    try FileManager.default.replaceItem(
        at: url, withItemAt: tempURL,
        backupItemName: nil, resultingItemURL: nil
    )
}

enum RatingError: LocalizedError {
    case cannotReadSource
    case cannotCreateMetadata
    case cannotSetTag
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cannotReadSource: return "Cannot read image file"
        case .cannotCreateMetadata: return "Cannot create metadata"
        case .cannotSetTag: return "Cannot set rating tag"
        case .cannotCreateDestination: return "Cannot create output file"
        case .writeFailed: return "Failed to write metadata"
        }
    }
}
