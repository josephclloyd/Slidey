# Sprint 35 — 2026-07-26

Started: 2026-07-26T14:30:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 313 | Saved filter presets | SlideshowView.swift (search bar integration), SlideyApp.swift (menu), ImageLoader.swift (predicate rebuild) | opus | — |
| 312 | Grid / contact sheet view | SlideshowView.swift (key binding, state), SlideshowView+Grid.swift (new) | opus | #313 |

## Excluded

(none — full backlog selected)

## Notes

- Both touch `SlideshowView.swift` → serialized: #313 → #312.
- **#313 baseline**: builds on #288's `urlFilter` + search bar state. `FilterPreset: Codable` struct with name, searchText, minRating, favouritesOnly, dateRange fields. Persist as JSON array in `@AppStorage`. Accessible via a presets popover on the search bar or a View menu. Unit tests for encode/decode and predicate reconstruction are required (this is testable logic, not pure UI).
- **#312 baseline**: `LazyVGrid` with adaptive columns. Thumbnails from the existing `NSCache` thumbnail cache (500-entry LRU). State: `@State var showGridView: Bool` (not private — extension needs it). All new view code in `SlideshowView+Grid.swift`; register in `project.pbxproj`. Respects active filter. Click → navigate to image + exit grid. SlideshowView.swift line limit: 3500.

## Results

Released: v1.34 — 2026-07-27

### Shipped
- #313 Saved filter presets — FilterPreset Codable model, @AppStorage JSON persistence, predicate rebuild, search bar popover; 16 unit tests
- #312 Grid / contact sheet view (Shift-T) — LazyVGrid, existing thumbnail cache, keyboard nav, filter-aware; 2 unit tests

### Needs attention
(none)

### Stats
- PRs merged: 2 (#319, #320)
- Total cost: ~$7.40
- Review rounds: 0 repairs (both clean first pass)
