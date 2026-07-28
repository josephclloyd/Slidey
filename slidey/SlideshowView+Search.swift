import SwiftUI

// Search / filter bar (#288): a toggleable top overlay (⌘F) that filters the
// current directory by filename substring and/or date-taken range. The filter
// is applied through the loader's existing `urlFilter` predicate, composed with
// the favourites/rating/duplicates filters in `updateFilter()`.
extension SlideshowView {

    /// Builds the pure `SearchCriteria` value from the current bar state.
    /// Date bounds are widened to whole days: start snaps to 00:00:00, end to
    /// 23:59:59, so a single day selected for both ends matches that day.
    var currentSearchCriteria: SearchCriteria {
        let calendar = Calendar.current
        let start = searchUseStartDate ? calendar.startOfDay(for: searchStartDate) : nil
        let end: Date?
        if searchUseEndDate {
            let startOfDay = calendar.startOfDay(for: searchEndDate)
            end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)
        } else {
            end = nil
        }
        return SearchCriteria(filenameQuery: searchFilenameQuery, startDate: start, endDate: end)
    }

    func toggleSearchBar() {
        if showSearchBar {
            closeSearchBar()
        } else {
            showSearchBar = true
            // Defer focus so the field exists before we make it first responder.
            DispatchQueue.main.async { searchFieldFocused = true }
        }
    }

    /// Hides the bar and clears the search filter. Clearing on close avoids a
    /// hidden-but-active filter mysteriously culling images with no visible UI.
    func closeSearchBar() {
        let wasActive = currentSearchCriteria.isActive
        showSearchBar = false
        searchFieldFocused = false
        searchFilenameQuery = ""
        searchUseStartDate = false
        searchUseEndDate = false
        if wasActive { updateFilter() }
    }

    /// Re-applies the combined filter after any search-state change. When a date
    /// bound is engaged it first ensures capture dates are resolved into the
    /// cache (off the main thread) so the predicate can stay filesystem-free.
    func applySearchFilter() {
        if currentSearchCriteria.needsDate {
            loadCaptureDatesThenFilter()
        } else {
            updateFilter()
        }
    }

    private func loadCaptureDatesThenFilter() {
        let missing = imageLoader.allImageURLs.filter { captureDateCache[$0] == nil }
        if missing.isEmpty {
            updateFilter()
            return
        }
        Task.detached(priority: .utility) {
            var resolved: [URL: Date] = [:]
            for url in missing {
                if let date = ImageLoader.dateTaken(for: url) { resolved[url] = date }
            }
            await MainActor.run {
                for (url, date) in resolved { self.captureDateCache[url] = date }
                self.updateFilter()
            }
        }
    }

    @ViewBuilder
    var searchBarOverlay: some View {
        if showSearchBar {
            VStack {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))

                    TextField("Filename contains\u{2026}", text: $searchFilenameQuery)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .frame(width: 200)
                        .focused($searchFieldFocused)
                        .onSubmit { searchFieldFocused = false }
                        .onChange(of: searchFilenameQuery) { _, _ in applySearchFilter() }

                    Divider().frame(height: 18)

                    Toggle("From", isOn: $searchUseStartDate)
                        .toggleStyle(.checkbox)
                        .onChange(of: searchUseStartDate) { _, _ in applySearchFilter() }
                    if searchUseStartDate {
                        DatePicker("", selection: $searchStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: searchStartDate) { _, _ in applySearchFilter() }
                    }

                    Toggle("To", isOn: $searchUseEndDate)
                        .toggleStyle(.checkbox)
                        .onChange(of: searchUseEndDate) { _, _ in applySearchFilter() }
                    if searchUseEndDate {
                        DatePicker("", selection: $searchEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: searchEndDate) { _, _ in applySearchFilter() }
                    }

                    Divider().frame(height: 18)

                    Text("\(imageLoader.imageURLs.count) / \(imageLoader.allImageURLs.count)")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(.caption, design: .monospaced))

                    Button {
                        showPresetsPopover.toggle()
                    } label: {
                        Image(systemName: "bookmark")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Saved filter presets")
                    .popover(isPresented: $showPresetsPopover, arrowEdge: .bottom) {
                        filterPresetsPopover
                    }

                    Button {
                        closeSearchBar()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close search (Esc)")
                }
                .font(.system(.body))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.75))
                .cornerRadius(8)
                .padding(.top, 20)
                .onExitCommand { closeSearchBar() }

                filterChipsRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75))
                    .cornerRadius(8)

                Spacer()
            }
        }
    }
}
