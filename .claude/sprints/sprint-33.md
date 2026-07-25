# Sprint 33 — 2026-07-22

Started: 2026-07-22T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 288 | Add search/filter by filename and date taken | ImageLoader.swift (filter logic), SlideshowView.swift (search bar overlay) | opus | — |
| 289 | Export slideshow as video | SlideshowView+VideoExport.swift (new), SlideyApp.swift (menu), SlideshowView.swift (.onReceive wiring only) | opus | #288 |

## Excluded

(none — full backlog selected)

## Notes

- Both issues touch SlideshowView.swift → serialized: #288 → #289.
- **#288 baseline**: `var urlFilter: ((URL) -> Bool)?` already exists in `ImageLoader.swift` and is wired into the scan pipeline. The predicate builder and search bar UI are the only new work. Check CLAUDE.md key binding registry before picking a key — many are taken.
- **#289 baseline**: `AVAssetWriter` is new to the codebase. Progress HUD should follow the tiled-ML cancellation pattern (between-frame cancel checks). Export must respect current filters (favourites/rating). Crossfade timing lives in `slideshowInterval` and `transitionsEnabled`. New file `SlideshowView+VideoExport.swift` must be registered in `project.pbxproj`.
- **After this sprint the backlog will be empty** — new issues needed before sprint 34.
