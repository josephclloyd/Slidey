import SwiftUI
import ImageIO
import CoreGraphics

extension SlideshowView {
    /// Toggles the "duplicates only" review mode. Turning it on hashes every
    /// image in the directory (off the main thread), groups near-duplicates,
    /// filters the view to just those images and reveals the thumbnail strip
    /// so the user can compare and cull. Turning it off restores the full set.
    func toggleDuplicatesMode() {
        if showDuplicatesOnly {
            showDuplicatesOnly = false
            duplicateURLStrings = []
            updateFilter()
            showDuplicatesToast("Showing all images")
            return
        }
        guard imageLoader.hasUnfilteredImages, !isDetectingDuplicates else { return }
        detectDuplicates()
    }

    private func detectDuplicates() {
        isDetectingDuplicates = true
        savedToast = "Scanning for duplicates…"
        savedToastIsError = false

        let urls = imageLoader.allImageURLs
        let generation = duplicateScanGeneration
        Task.detached(priority: .userInitiated) {
            var hashes: [(url: URL, hash: UInt64)] = []
            hashes.reserveCapacity(urls.count)
            for url in urls {
                guard let cgImage = Self.duplicateHashImage(url: url),
                      let hash = DuplicateDetector.perceptualHash(cgImage) else { continue }
                hashes.append((url, hash))
            }
            let groups = DuplicateDetector.groupDuplicates(hashes)
            let duplicateSet = Set(groups.flatMap { $0 }.map { $0.absoluteString })
            let groupCount = groups.count
            let imageCount = duplicateSet.count

            await MainActor.run {
                guard generation == self.duplicateScanGeneration else { return }
                self.isDetectingDuplicates = false
                guard !duplicateSet.isEmpty else {
                    self.showDuplicatesToast("No duplicates found")
                    return
                }
                self.duplicateURLStrings = duplicateSet
                self.showDuplicatesOnly = true
                self.updateFilter()
                self.showThumbnails = true
                let plural = groupCount == 1 ? "" : "s"
                self.showDuplicatesToast("\(imageCount) images in \(groupCount) duplicate group\(plural)")
            }
        }
    }

    /// Combines the favourites, minimum-rating and duplicates filters into a
    /// single `urlFilter` predicate on the image loader. Setting it to nil when
    /// no filter is active restores the full image set.
    func updateFilter() {
        let wantFavs = showFavouritesOnly
        let minRating = minimumRatingFilter
        let wantDupes = showDuplicatesOnly
        let favs = favouriteURLStrings
        let ratings = imageRatings
        let dupes = duplicateURLStrings

        if !wantFavs && minRating <= 0 && !wantDupes {
            imageLoader.urlFilter = nil
        } else {
            imageLoader.urlFilter = { url in
                if wantFavs && !favs.contains(url.absoluteString) { return false }
                if minRating > 0 && (ratings[url] ?? 0) < minRating { return false }
                if wantDupes && !dupes.contains(url.absoluteString) { return false }
                return true
            }
        }
    }

    var filterEmptyStateHint: String {
        if showDuplicatesOnly {
            return "Press D to leave duplicates view"
        }
        if showFavouritesOnly {
            return "Press x to favourite images, then v to filter"
        }
        return "Rate images with 1\u{2013}5, then filter from the Slideshow menu"
    }

    private func showDuplicatesToast(_ message: String) {
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }

    /// Reads a tiny thumbnail (never the full bitmap) for hashing. 32 px is
    /// far larger than the 9×8 grid dHash needs but keeps enough detail for a
    /// stable hash while staying cheap for very large source files.
    nonisolated private static func duplicateHashImage(url: URL, maxPixelSize: Int = 32) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
