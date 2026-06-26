import Foundation
import AppKit
import ImageIO

enum AppSortOrder: String, CaseIterable, Identifiable {
    case creationDateAscending
    case creationDateDescending
    case modificationDateAscending
    case modificationDateDescending
    case captureDateAscending
    case captureDateDescending
    case nameAscending
    case nameDescending
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .creationDateAscending: return "Creation Date (Oldest First)"
        case .creationDateDescending: return "Creation Date (Newest First)"
        case .modificationDateAscending: return "Modification Date (Oldest First)"
        case .modificationDateDescending: return "Modification Date (Newest First)"
        case .captureDateAscending: return "Capture Date (Oldest First)"
        case .captureDateDescending: return "Capture Date (Newest First)"
        case .nameAscending: return "Name (A → Z)"
        case .nameDescending: return "Name (Z → A)"
        case .random: return "Random"
        }
    }
}

class ImageLoader: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var currentIndex: Int = 0
    @Published var currentImage: NSImage?
    @Published var directoryMissing: Bool = false

    private(set) var allImageURLs: [URL] = []
    var urlFilter: ((URL) -> Bool)? {
        didSet { reapplyFilter() }
    }
    var hasUnfilteredImages: Bool { !allImageURLs.isEmpty }

    let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]

    /// Maximum decoded pixel count we will accept. Guards against
    /// decompression bombs - small files that decode to enormous bitmaps and
    /// exhaust memory. 200 megapixels is generous (a 50 MP camera frame
    /// upscaled 4x is ~200 MP) but still bounded.
    private let maxPixelCount = 200_000_000

    /// Number of neighbours on each side of the current image to keep decoded
    /// in memory. Bounds resident memory regardless of folder size.
    private let cacheRadius = 1

    /// Coalesce window for filesystem events. A burst of writes (e.g. unzip
    /// into the directory) collapses into a single rescan after this delay.
    private let rescanDebounce: DispatchTimeInterval = .milliseconds(500)

    private var cache: [Int: NSImage] = [:]
    private var directoryURL: URL?
    private var watcherSource: DispatchSourceFileSystemObject?
    private var rescanWorkItem: DispatchWorkItem?
    private var recoveryTimer: DispatchSourceTimer?

    /// Sort applied to scan results. Set by SlideshowView from @AppStorage so
    /// menu and Settings changes flow into the next scan/rescan.
    var sortOrder: AppSortOrder = .creationDateAscending

    var currentImageURL: URL? {
        guard !imageURLs.isEmpty && currentIndex < imageURLs.count else { return nil }
        return imageURLs[currentIndex]
    }

    func loadImagesFromDirectory(url: URL, jumpTo targetURL: URL? = nil) {
        let urls = scanDirectory(url: url)

        DispatchQueue.main.async {
            self.stopWatching()
            self.directoryMissing = false
            self.directoryURL = url
            self.cache.removeAll()
            self.allImageURLs = urls
            let filtered = self.urlFilter.map { filter in urls.filter(filter) } ?? urls
            self.imageURLs = filtered
            if let target = targetURL, let idx = filtered.firstIndex(of: target) {
                self.currentIndex = idx
            } else {
                self.currentIndex = 0
            }
            self.currentImage = self.loadImage(at: self.currentIndex)
            self.preloadNeighbours()
            self.startWatching(url: url)
        }
    }

    func jumpTo(url: URL) {
        guard let index = imageURLs.firstIndex(of: url) else { return }
        jumpTo(index: index)
    }

    private func scanDirectory(url: URL) -> [URL] {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = []
        let needsCaptureDate = sortOrder == .captureDateAscending || sortOrder == .captureDateDescending

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard let r = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]),
                  r.isRegularFile == true else {
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let captureDate = needsCaptureDate ? Self.exifCaptureDate(for: fileURL) : nil
            entries.append((
                url: fileURL,
                created: r.creationDate ?? Date.distantPast,
                modified: r.contentModificationDate ?? Date.distantPast,
                captured: captureDate
            ))
        }

        Self.sortEntries(&entries, by: sortOrder)

        return entries.map { $0.url }
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func exifCaptureDate(for url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else {
            return nil
        }
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
        guard let ds = dateString else { return nil }
        return exifDateFormatter.date(from: ds)
    }

    static func sortEntries(_ entries: inout [(url: URL, created: Date, modified: Date, captured: Date?)], by order: AppSortOrder) {
        switch order {
        case .creationDateAscending:
            entries.sort { $0.created < $1.created }
        case .creationDateDescending:
            entries.sort { $0.created > $1.created }
        case .modificationDateAscending:
            entries.sort { $0.modified < $1.modified }
        case .modificationDateDescending:
            entries.sort { $0.modified > $1.modified }
        case .captureDateAscending:
            entries.sort {
                switch ($0.captured, $1.captured) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
                }
            }
        case .captureDateDescending:
            entries.sort {
                switch ($0.captured, $1.captured) {
                case let (a?, b?): return a > b
                case (nil, _?): return true
                case (_?, nil): return false
                case (nil, nil): return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
                }
            }
        case .nameAscending:
            entries.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        case .nameDescending:
            entries.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedDescending }
        case .random:
            entries.shuffle()
        }
    }

    /// Re-runs the scan with the current `sortOrder` and reconciles the
    /// displayed image's index by URL. Use after changing sortOrder.
    func applySort() {
        rescanDirectory()
    }

    func nextImage() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % imageURLs.count
        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    func jumpTo(index: Int) {
        guard imageURLs.indices.contains(index) else { return }
        currentIndex = index
        currentImage = loadImage(at: index)
        preloadNeighbours()
    }

    func previousImage() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    func renameImage(from oldURL: URL, to newURL: URL) {
        if let idx = allImageURLs.firstIndex(of: oldURL) {
            allImageURLs[idx] = newURL
        }
        if let idx = imageURLs.firstIndex(of: oldURL) {
            imageURLs[idx] = newURL
        }
    }

    func removeImage(at url: URL) {
        allImageURLs.removeAll { $0 == url }
        guard let index = imageURLs.firstIndex(of: url) else { return }
        imageURLs.remove(at: index)
        cache.removeAll()

        if imageURLs.isEmpty {
            currentIndex = 0
            currentImage = nil
            return
        }

        if index < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= imageURLs.count {
            currentIndex = imageURLs.count - 1
        }

        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    func insertImage(url: URL, at index: Int, allIndex: Int) {
        let clampedAllIndex = min(allIndex, allImageURLs.count)
        allImageURLs.insert(url, at: clampedAllIndex)

        if urlFilter == nil || urlFilter?(url) == true {
            let clampedIndex = min(index, imageURLs.count)
            imageURLs.insert(url, at: clampedIndex)
            cache.removeAll()
            jumpTo(index: clampedIndex)
        }
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

    private func startWatching(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.handleDirectoryGone()
            } else {
                self.scheduleRescan()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        watcherSource = source
        source.resume()
    }

    private func handleDirectoryGone() {
        guard let url = directoryURL else { return }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            scheduleRescan()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopWatching()
            self.directoryMissing = true
            self.startRecoveryPolling()
        }
    }

    private func startRecoveryPolling() {
        stopRecoveryPolling()
        guard let url = directoryURL else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists && isDir.boolValue {
                DispatchQueue.main.async {
                    self.stopRecoveryPolling()
                    self.directoryMissing = false
                    self.loadImagesFromDirectory(url: url)
                }
            }
        }
        recoveryTimer = timer
        timer.resume()
    }

    private func stopRecoveryPolling() {
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private func stopWatching() {
        watcherSource?.cancel()
        watcherSource = nil
        rescanWorkItem?.cancel()
        rescanWorkItem = nil
        stopRecoveryPolling()
    }

    /// Coalesce a burst of filesystem events into a single rescan.
    private func scheduleRescan() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rescanWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.rescanDirectory()
            }
            self.rescanWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.rescanDebounce, execute: work)
        }
    }

    private func rescanDirectory() {
        guard let url = directoryURL else { return }
        let newURLs = scanDirectory(url: url)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if newURLs == self.allImageURLs { return }

            let previousURL = self.currentImageURL
            self.cache.removeAll()
            self.allImageURLs = newURLs
            let filtered = self.urlFilter.map { filter in newURLs.filter(filter) } ?? newURLs
            self.imageURLs = filtered

            if filtered.isEmpty {
                self.currentIndex = 0
                self.currentImage = nil
                return
            }

            if let prev = previousURL, let idx = filtered.firstIndex(of: prev) {
                self.currentIndex = idx
            } else {
                self.currentIndex = min(self.currentIndex, filtered.count - 1)
            }
            self.currentImage = self.loadImage(at: self.currentIndex)
            self.preloadNeighbours()
        }
    }

    private func reapplyFilter() {
        let filtered = urlFilter.map { filter in allImageURLs.filter(filter) } ?? allImageURLs
        if filtered == imageURLs { return }
        let previousURL = currentImageURL
        cache.removeAll()
        imageURLs = filtered
        if filtered.isEmpty {
            currentIndex = 0
            currentImage = nil
            return
        }
        if let prev = previousURL, let idx = filtered.firstIndex(of: prev) {
            currentIndex = idx
        } else {
            currentIndex = min(currentIndex, filtered.count - 1)
        }
        currentImage = loadImage(at: currentIndex)
        preloadNeighbours()
    }

    deinit {
        stopWatching()
    }
}
