# Sprint 9 — 2026-06-11

Started: 2026-06-11T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 72 | Remove Roadmap / TODO from README | README.md | opus | — |
| 59 | Expand SlideyApp test coverage (Settings, Music menu wiring) | SlideyAppTests.swift | opus | — |
| 63 | Persist zoom level and pan offset per image across navigation | SlideshowView.swift, ZoomPanController.swift | opus | — |
| 65 | Star/favourite images with a key (persistent) | SlideshowView.swift, SlideyApp.swift | opus | #63 |
| 58 | Expand SlideshowView test coverage | SlideshowViewTests.swift | opus | #63, #65 |

## Excluded

- #60 SwiftLint — too broad alongside active SlideshowView feature work; better as a standalone sprint once features settle

## Notes

- Wave 1 (parallel): #72, #59, #63 — all independent, no file conflicts
- Wave 2: #65 — blocked by #63 (both touch SlideshowView.swift)
- Wave 3: #58 — blocked by #63 + #65 (tests should cover new zoom/pan and star state)
- #66 (extraction) merged in Sprint 8; SlideshowView.swift is now 1,643 lines — #63 and #65 are unblocked
- Author trust filter: all issues filed by `josephclloyd` ✓
