import SwiftUI

// Multi-select mode: shows every image in the active (filtered) set as a
// selectable contact sheet. Clicking a thumbnail toggles its membership in
// `selectedURLs`; a toolbar applies batch rating, favouriting, or trashing to
// the whole selection. Toggled with ⌥⌘S (menu) and exited with Escape.
extension SlideshowView {
    @ViewBuilder
    var selectionOverlay: some View {
        if selectionModeActive {
            SelectionContactSheet(
                imageLoader: imageLoader,
                favouriteURLStrings: favouriteURLStrings,
                selectedURLs: selectedURLs,
                columnCount: $gridColumnCount,
                onToggle: { url in toggleSelection(url) },
                onRate: { rating in batchSetRating(rating) },
                onFavourite: { batchFavourite() },
                onDelete: { batchDeleteToTrash() },
                onDone: { exitSelectionMode() }
            )
            .transition(.opacity)
            .zIndex(2)
        }
    }

    func toggleSelectionMode() {
        if selectionModeActive {
            exitSelectionMode()
        } else {
            guard !imageLoader.imageURLs.isEmpty else { return }
            selectedURLs.removeAll()
            // Seed with the image currently on screen so there's an immediate
            // selection to act on.
            if let current = imageLoader.currentImageURL {
                selectedURLs.insert(current)
            }
            selectionModeActive = true
        }
    }

    func exitSelectionMode() {
        selectionModeActive = false
        selectedURLs.removeAll()
    }

    func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func handleSelectionKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.key == .escape {
            exitSelectionMode()
            return .handled
        }
        if keyPress.key == .delete {
            batchDeleteToTrash()
            return .handled
        }
        switch keyPress.characters {
        case "0", "1", "2", "3", "4", "5":
            if let rating = Int(keyPress.characters) { batchSetRating(rating) }
        case "f", "F":
            batchFavourite()
        default:
            break
        }
        // Swallow every key so edit/navigation shortcuts can't fire on the
        // hidden image underneath the contact sheet.
        return .handled
    }

    // MARK: - Batch actions

    func batchSetRating(_ rating: Int) {
        let urls = Array(selectedURLs)
        guard !urls.isEmpty else { return }
        let clamped = max(0, min(5, rating))

        for url in urls {
            if clamped == 0 {
                imageRatings.removeValue(forKey: url)
            } else {
                imageRatings[url] = clamped
            }
        }
        if minimumRatingFilter > 0 { updateFilter() }

        Task.detached(priority: .utility) {
            for url in urls {
                try? writeRatingToFile(url: url, rating: clamped)
            }
        }

        let noun = urls.count == 1 ? "image" : "images"
        let message = clamped == 0
            ? "Cleared rating on \(urls.count) \(noun)"
            : "Rated \(urls.count) \(noun) " + String(repeating: "\u{2605}", count: clamped)
        showSelectionToast(message)
    }

    func batchFavourite() {
        let urls = Array(selectedURLs)
        guard !urls.isEmpty else { return }
        for url in urls {
            favouriteURLStrings.insert(url.absoluteString)
        }
        saveFavourites()
        if showFavouritesOnly { updateFilter() }
        let noun = urls.count == 1 ? "image" : "images"
        showSelectionToast("\u{2605} Favourited \(urls.count) \(noun)")
    }

    func batchDeleteToTrash() {
        let urls = Array(selectedURLs)
        guard !urls.isEmpty else { return }

        let noun = urls.count == 1 ? "image" : "images"
        let alert = NSAlert()
        alert.messageText = "Move \(urls.count) \(noun) to Trash?"
        alert.informativeText = "You can restore these files from the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        let perform: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            var trashed = 0
            var failed = 0
            for url in urls {
                do {
                    // Removing the URL from the loader mutates `imageURLs`,
                    // which fires `onImageURLsChanged` and prunes all
                    // per-image state (ratings, edits, and `selectedURLs`).
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    self.imageLoader.removeImage(at: url)
                    trashed += 1
                } catch {
                    failed += 1
                }
            }
            self.selectedURLs.removeAll()
            self.selectionModeActive = false
            if failed > 0 {
                self.showErrorToast("Trashed \(trashed), \(failed) failed")
            } else {
                let done = trashed == 1 ? "image" : "images"
                self.showSelectionToast("Moved \(trashed) \(done) to Trash")
            }
        }

        if let window = myWindow ?? NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: perform)
        } else {
            perform(alert.runModal())
        }
    }

    private func showSelectionToast(_ message: String) {
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if savedToast == message { savedToast = nil }
        }
    }
}

struct SelectionContactSheet: View {
    @ObservedObject var imageLoader: ImageLoader
    var favouriteURLStrings: Set<String> = []
    let selectedURLs: Set<URL>
    @Binding var columnCount: Int
    let onToggle: (URL) -> Void
    let onRate: (Int) -> Void
    let onFavourite: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    private let thumbSize: CGFloat = 140
    private let spacing: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize), spacing: spacing)]
    }

    private var hasSelection: Bool { !selectedURLs.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geo in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(imageLoader.imageURLs.enumerated()), id: \.element) { pair in
                            selectableCell(for: pair.element)
                        }
                    }
                    .padding(spacing)
                }
                .onAppear { updateColumnCount(width: geo.size.width) }
                .onChange(of: geo.size.width) { _, width in updateColumnCount(width: width) }
            }
        }
        .background(.black.opacity(0.92))
        .accessibilityLabel("Selection mode, \(selectedURLs.count) of \(imageLoader.imageURLs.count) images selected")
    }

    private func selectableCell(for url: URL) -> some View {
        let isSelected = selectedURLs.contains(url)
        return ZStack(alignment: .topLeading) {
            ThumbnailCell(
                url: url,
                size: thumbSize,
                isSelected: isSelected,
                isFavourite: favouriteURLStrings.contains(url.absoluteString),
                onTap: { onToggle(url) }
            )
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(4)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("\(selectedURLs.count) selected")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 100, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { rating in
                    Button("\u{2605}\(rating)") { onRate(rating) }
                        .disabled(!hasSelection)
                }
                Button("Clear") { onRate(0) }
                    .disabled(!hasSelection)
            }

            Button("\u{2605} Favourite") { onFavourite() }
                .disabled(!hasSelection)

            Button("Delete\u{2026}") { onDelete() }
                .disabled(!hasSelection)

            Spacer()

            Button("Done") { onDone() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.85))
    }

    private func updateColumnCount(width: CGFloat) {
        guard width > 0 else { return }
        let count = max(1, Int((width - spacing) / (thumbSize + spacing)))
        if count != columnCount { columnCount = count }
    }
}
