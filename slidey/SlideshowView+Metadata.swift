import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ImageMetadata: Equatable {
    var caption: String
    var keywords: String   // comma-separated for editing
    var copyright: String

    static let empty = ImageMetadata(caption: "", keywords: "", copyright: "")

    var keywordList: [String] {
        keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct MetadataEditorView: View {
    let url: URL
    let onSave: (ImageMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metadata = ImageMetadata.empty
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Metadata")
                .font(.headline)
            Text(url.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Form {
                TextField("Caption", text: $metadata.caption, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($captionFocused)
                TextField("Keywords (comma-separated)", text: $metadata.keywords)
                TextField("Copyright", text: $metadata.copyright)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(metadata)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            metadata = SlideshowView.readImageMetadata(for: url)
            captionFocused = true
        }
    }
}

extension SlideshowView {

    func openMetadataEditor() {
        guard imageLoader.currentImageURL != nil, imageLoader.currentImage != nil else { return }
        guard !slideshow.isPlaying else { return }
        showMetadataEditor = true
    }

    /// Writes the edited metadata to the source file on disk. Unlike the app's
    /// pixel edits (which stay in-memory), metadata editing intentionally
    /// modifies the original file.
    func saveImageMetadata(_ metadata: ImageMetadata, to url: URL) {
        if SlideshowView.writeImageMetadata(metadata, to: url) {
            showSavedToast(filename: url.lastPathComponent)
        } else {
            showErrorToast("Could not write metadata to \(url.lastPathComponent)")
        }
    }

    static func readImageMetadata(for url: URL) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .empty
        }
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let caption = (iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String)
            ?? (tiff?[kCGImagePropertyTIFFImageDescription] as? String)
            ?? ""
        let keywords = (iptc?[kCGImagePropertyIPTCKeywords] as? [String]) ?? []
        let copyright = (tiff?[kCGImagePropertyTIFFCopyright] as? String)
            ?? (iptc?[kCGImagePropertyIPTCCopyrightNotice] as? String)
            ?? ""

        return ImageMetadata(
            caption: caption,
            keywords: keywords.joined(separator: ", "),
            copyright: copyright
        )
    }

    /// Merges the edited fields into the file's existing metadata and rewrites the
    /// image in place, preserving pixel data and all other properties. Returns
    /// `false` if the source can't be read or the destination can't be finalized.
    @discardableResult
    static func writeImageMetadata(_ metadata: ImageMetadata, to url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            return false
        }

        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var iptc = (props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
        var tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]

        // CGImageDestinationAddImageFromSource merges these properties over the
        // file's existing embedded metadata, so omitting a key leaves the old
        // value intact. To clear a field it must be explicitly set to kCFNull.
        let caption = metadata.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.isEmpty {
            iptc[kCGImagePropertyIPTCCaptionAbstract] = kCFNull
            tiff[kCGImagePropertyTIFFImageDescription] = kCFNull
        } else {
            iptc[kCGImagePropertyIPTCCaptionAbstract] = caption
            tiff[kCGImagePropertyTIFFImageDescription] = caption
        }

        let keywords = metadata.keywordList
        if keywords.isEmpty {
            iptc[kCGImagePropertyIPTCKeywords] = kCFNull
        } else {
            iptc[kCGImagePropertyIPTCKeywords] = keywords
        }

        let copyright = metadata.copyright.trimmingCharacters(in: .whitespacesAndNewlines)
        if copyright.isEmpty {
            tiff[kCGImagePropertyTIFFCopyright] = kCFNull
            iptc[kCGImagePropertyIPTCCopyrightNotice] = kCFNull
        } else {
            tiff[kCGImagePropertyTIFFCopyright] = copyright
            iptc[kCGImagePropertyIPTCCopyrightNotice] = copyright
        }

        props[kCGImagePropertyIPTCDictionary] = iptc
        props[kCGImagePropertyTIFFDictionary] = tiff

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".slidey-metadata-\(UUID().uuidString).tmp")

        guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, type, 1, nil) else {
            return false
        }
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }
}
