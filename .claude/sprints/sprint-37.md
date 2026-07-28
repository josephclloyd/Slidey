# Sprint 37 — 2026-07-28

Started: 2026-07-28T15:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 330 | Move current image to Trash | ImageLoader.swift (trashCurrentImage), SlideshowView.swift (key handler, toast), SlideyApp.swift (menu item) | opus | — |
| 327 | Crop aspect ratio presets | SlideshowView+Crop.swift (preset logic, constrained drag), CropController | opus | #330 |
| 331 | Orientation and file-type filter chips | ImageLoader.swift (predicate, dimension cache), SlideshowView.swift (filter bar UI) | opus | #327 |

## Excluded

- #325 Sync pan/zoom between compare panes — compare mode just had two PRs land (#323, #324); let it settle
- #326 Compare any two images — large sheet UI; save for a compare-focused sprint
- #328 Selective colour — CIColorCube/Metal complexity; deserves a dedicated sprint
- #329 Multi-select — large scope; depends on #330's trashItem logic; follow-on sprint
- #332 Video playback — largest scope in the backlog; own sprint

## Notes

- All three issues serialize: #330 → #327 → #331. #330 and #331 both touch `ImageLoader.swift` and `SlideshowView.swift`; #327 is contained to the crop subsystem but may touch `SlideshowView.swift` if it needs new `@State`.
- **#330 baseline**: `ImageLoader.trashCurrentImage()` calls `FileManager.default.trashItem(at:resultingItemURL:)`, removes the URL from `imageURLs`, advances index (or steps back if last). Key binding: `⌫` (Delete) — verify free in CLAUDE.md registry. Toast with filename. Unit-test the index-advance logic in `ImageLoaderTests`.
- **#327 baseline**: Preset enum (Free, 1:1, 4:3, 3:2, 16:9, A4Portrait, A4Landscape) in `CropController`. On handle drag with active preset: recalculate perpendicular dimension from ratio. Preset button bar in the crop HUD overlay. Persist last-used in `@AppStorage`. On preset tap with existing rect: resize to ratio centred on rect centre.
- **#331 baseline**: Orientation filter uses cached image dimensions (add to the thumbnail-generation pass: store width/height in a `[URL: CGSize]` dict on `ImageLoader`). File-type filter on `url.pathExtension.lowercased()`. Both extend the same `urlFilter` predicate rebuilt by `applyFilter()` (established in #313). Unit-test predicate composition in `ImageLoaderTests`.
