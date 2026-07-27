import SwiftUI

/// A named, persisted snapshot of the search + filter state (#313). Built on top
/// of #288's search/filter infrastructure so applying a preset reproduces exactly
/// the same visible set as typing the criteria into the search bar by hand.
///
/// `startDate`/`endDate` are the raw user-picked days; `nil` means "any date".
/// They are widened to whole-day bounds (start → 00:00:00, end → 23:59:59) inside
/// `searchCriteria`, matching `SlideshowView.currentSearchCriteria`.
struct FilterPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var searchText: String = ""
    var startDate: Date?
    var endDate: Date?
    var minRating: Int = 0
    var favouritesOnly: Bool = false

    /// Rebuilds the same `SearchCriteria` the live search bar produces for this
    /// preset's filename + date-range fields, so the predicate filters identically.
    var searchCriteria: SearchCriteria {
        let calendar = Calendar.current
        let start = startDate.map { calendar.startOfDay(for: $0) }
        let end = endDate.map { day -> Date in
            let startOfDay = calendar.startOfDay(for: day)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? day
        }
        return SearchCriteria(filenameQuery: searchText, startDate: start, endDate: end)
    }

    /// True when this preset would actually constrain the visible set.
    var isActive: Bool {
        searchCriteria.isActive || minRating > 0 || favouritesOnly
    }

    /// One-line human-readable description of the constraints, for the popover.
    var summary: String {
        var parts: [String] = []
        let query = searchCriteria.trimmedQuery
        if !query.isEmpty { parts.append("\u{201C}\(query)\u{201D}") }
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter
        }()
        if let start = startDate, let end = endDate {
            parts.append("\(dateFormatter.string(from: start))\u{2013}\(dateFormatter.string(from: end))")
        } else if let start = startDate {
            parts.append("from \(dateFormatter.string(from: start))")
        } else if let end = endDate {
            parts.append("to \(dateFormatter.string(from: end))")
        }
        if minRating > 0 { parts.append("\u{2265} \(minRating)\u{2605}") }
        if favouritesOnly { parts.append("favourites") }
        return parts.isEmpty ? "No constraints" : parts.joined(separator: " \u{00B7} ")
    }

    /// Reconstructs a loader-compatible predicate from this preset alone. Mirrors
    /// the shape of `SlideshowView.updateFilter()` (favourites → rating → search)
    /// so a preset applied through the UI and this pure rebuild agree. Returns
    /// `nil` when the preset imposes no constraints (restores the full set).
    func makeURLFilter(
        favouriteURLStrings: Set<String>,
        ratings: [URL: Int],
        captureDates: [URL: Date]
    ) -> ((URL) -> Bool)? {
        guard isActive else { return nil }
        let criteria = searchCriteria
        let wantFavs = favouritesOnly
        let minRating = self.minRating
        return { url in
            if wantFavs && !favouriteURLStrings.contains(url.absoluteString) { return false }
            if minRating > 0 && (ratings[url] ?? 0) < minRating { return false }
            if criteria.isActive && !criteria.matches(url: url, captureDate: captureDates[url]) { return false }
            return true
        }
    }
}

extension SlideshowView {

    /// JSON-array-backed access to the persisted presets. Reads/writes the
    /// `@AppStorage("filterPresets")` blob so presets survive relaunches.
    var filterPresets: [FilterPreset] {
        get { (try? JSONDecoder().decode([FilterPreset].self, from: filterPresetsData)) ?? [] }
        nonmutating set { filterPresetsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// True when the live search/filter state would constrain the visible set —
    /// used to gate saving an empty preset.
    var currentFilterIsActive: Bool {
        currentSearchCriteria.isActive || minimumRatingFilter > 0 || showFavouritesOnly
    }

    /// Captures the current search bar + rating + favourites state as a new named
    /// preset. No-op on a blank name.
    func saveCurrentFilterAsPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = FilterPreset(
            name: trimmed,
            searchText: searchFilenameQuery,
            startDate: searchUseStartDate ? searchStartDate : nil,
            endDate: searchUseEndDate ? searchEndDate : nil,
            minRating: minimumRatingFilter,
            favouritesOnly: showFavouritesOnly
        )
        var presets = filterPresets
        presets.append(preset)
        filterPresets = presets
    }

    /// Applies a preset by driving the live search/filter state, then re-runs the
    /// combined filter through the existing pipeline (resolving capture dates
    /// first when a date bound is engaged).
    func applyPreset(_ preset: FilterPreset) {
        searchFilenameQuery = preset.searchText
        if let start = preset.startDate {
            searchUseStartDate = true
            searchStartDate = start
        } else {
            searchUseStartDate = false
        }
        if let end = preset.endDate {
            searchUseEndDate = true
            searchEndDate = end
        } else {
            searchUseEndDate = false
        }
        minimumRatingFilter = preset.minRating
        showFavouritesOnly = preset.favouritesOnly
        if preset.searchCriteria.isActive { showSearchBar = true }
        applySearchFilter()
    }

    func deletePreset(_ preset: FilterPreset) {
        filterPresets.removeAll { $0.id == preset.id }
    }

    /// Popover anchored to the bookmark button in the search bar. Delegates to
    /// `FilterPresetsPopover`, which owns its own name-field state.
    @ViewBuilder
    var filterPresetsPopover: some View {
        FilterPresetsPopover(
            presets: filterPresets,
            canSave: currentFilterIsActive,
            onApply: { preset in
                applyPreset(preset)
                showPresetsPopover = false
            },
            onDelete: { deletePreset($0) },
            onSave: { saveCurrentFilterAsPreset(name: $0) }
        )
    }
}

/// Saved-presets list with apply/delete rows and a name field to save the current
/// filter (#313). Kept a standalone view so its transient name-field state lives
/// here rather than bloating `SlideshowView`.
struct FilterPresetsPopover: View {
    let presets: [FilterPreset]
    let canSave: Bool
    let onApply: (FilterPreset) -> Void
    let onDelete: (FilterPreset) -> Void
    let onSave: (String) -> Void

    @State private var newPresetName = ""

    private var trimmedName: String {
        newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Presets")
                .font(.headline)

            if presets.isEmpty {
                Text("No saved presets yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(presets) { preset in
                    HStack(spacing: 8) {
                        Button {
                            onApply(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                Text(preset.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Apply this preset")

                        Button {
                            onDelete(preset)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this preset")
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
                Button("Save") { commit() }
                    .disabled(trimmedName.isEmpty || !canSave)
            }
            if !canSave {
                Text("Set a search, rating or favourites filter to save a preset.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func commit() {
        guard !trimmedName.isEmpty, canSave else { return }
        onSave(trimmedName)
        newPresetName = ""
    }
}
