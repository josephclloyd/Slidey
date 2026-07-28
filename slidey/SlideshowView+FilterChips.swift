import SwiftUI

/// Orientation classes for the filter chips (#331). `.all` is the neutral state
/// that imposes no constraint. Classification is done on the orientation-corrected
/// pixel size from `ImageLoader.pixelDimensions(for:)`, so it matches how the image
/// actually displays rather than how its pixels happen to be stored.
enum OrientationFilter: String, CaseIterable, Identifiable {
    case all
    case portrait
    case landscape
    case square

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        case .square: return "Square"
        }
    }

    /// True when an image of the given (display-corrected) size belongs to this
    /// orientation class. `.all` matches everything.
    func matches(size: CGSize) -> Bool {
        switch self {
        case .all: return true
        case .portrait: return size.height > size.width
        case .landscape: return size.width > size.height
        case .square: return size.width == size.height
        }
    }
}

/// File-type classes for the multi-select filter chips (#331). Each case maps to
/// the lowercased path extensions it covers; classification never touches the
/// filesystem — it reads `url.pathExtension` only.
enum FileTypeFilter: String, CaseIterable, Identifiable {
    case jpeg
    case heic
    case png
    case gif
    case tiff
    case webp
    case bmp
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png: return "PNG"
        case .gif: return "GIF"
        case .tiff: return "TIFF"
        case .webp: return "WebP"
        case .bmp: return "BMP"
        case .raw: return "RAW"
        }
    }

    /// Lowercased extensions this class covers. Mirrors `ImageLoader.supportedExtensions`.
    var extensions: Set<String> {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .heic: return ["heic"]
        case .png: return ["png"]
        case .gif: return ["gif"]
        case .tiff: return ["tiff", "tif"]
        case .webp: return ["webp"]
        case .bmp: return ["bmp"]
        case .raw: return ["cr2", "cr3", "nef", "arw", "dng", "raf", "orf", "rw2", "pef", "srw"]
        }
    }

    /// True when `url`'s extension belongs to any of the selected classes. An
    /// empty selection means "no file-type constraint" and matches everything.
    static func matchesAny(_ selected: Set<FileTypeFilter>, url: URL) -> Bool {
        guard !selected.isEmpty else { return true }
        let ext = url.pathExtension.lowercased()
        return selected.contains { $0.extensions.contains(ext) }
    }
}

extension SlideshowView {

    /// True when either chip group would constrain the visible set. Used to gate
    /// the empty-state view and the `urlFilter == nil` shortcut in `updateFilter()`.
    var chipFilterActive: Bool {
        orientationFilter != .all || !fileTypeFilter.isEmpty
    }

    func setOrientationFilter(_ option: OrientationFilter) {
        guard orientationFilter != option else { return }
        orientationFilter = option
        applyChipFilter()
    }

    func toggleFileType(_ type: FileTypeFilter) {
        if fileTypeFilter.contains(type) {
            fileTypeFilter.remove(type)
        } else {
            fileTypeFilter.insert(type)
        }
        applyChipFilter()
    }

    /// Re-applies the combined filter after a chip change. The orientation filter
    /// needs pixel dimensions, so it resolves them (off the main thread) into the
    /// cache first, keeping the predicate itself filesystem-free — same shape as
    /// `applySearchFilter()` resolving capture dates for the date bound.
    func applyChipFilter() {
        if orientationFilter != .all {
            loadDimensionsThenFilter()
        } else {
            updateFilter()
        }
    }

    private func loadDimensionsThenFilter() {
        let missing = imageLoader.allImageURLs.filter { dimensionCache[$0] == nil }
        if missing.isEmpty {
            updateFilter()
            return
        }
        Task.detached(priority: .utility) {
            var resolved: [URL: CGSize] = [:]
            for url in missing {
                if let size = ImageLoader.pixelDimensions(for: url) { resolved[url] = size }
            }
            await MainActor.run {
                for (url, size) in resolved { self.dimensionCache[url] = size }
                self.updateFilter()
            }
        }
    }

    /// Chip rows shown as a second line inside the search bar overlay. Kept out of
    /// `SlideshowView.body`/`coreView` (which are near the type-checker limit) by
    /// living in this extension.
    @ViewBuilder
    var filterChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(OrientationFilter.allCases) { option in
                chipButton(title: option.label, isOn: orientationFilter == option) {
                    setOrientationFilter(option)
                }
            }

            Divider().frame(height: 16)

            ForEach(FileTypeFilter.allCases) { type in
                chipButton(title: type.label, isOn: fileTypeFilter.contains(type)) {
                    toggleFileType(type)
                }
            }
        }
    }

    private func chipButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor : Color.white.opacity(0.12))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove \(title) filter" : "Filter to \(title)")
    }
}
