# Sprint 7 — 2026-06-04

Started: 2026-06-04T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 46 | Notifications.swift enum | `SlideshowView.swift`, `SlideyApp.swift`, new `Notifications.swift` | opus | — |
| 47 | Update CLAUDE.md and README | docs only | opus | — |
| 48 | Home/End keys to jump to first/last image | `SlideshowView.swift` | opus | #46 |
| 49 | Remember window size and position | `SlideyApp.swift` | opus | #46 |
| 50 | Pixel dimensions + file size in info overlay | `SlideshowView.swift` | opus | #48 |

## Excluded

- D (Slideshow loop mode) — already implemented: `nextImage()` uses `% imageURLs.count`, wraps naturally.

## Notes

- Sprint 7 = introspection sprint. Findings that drove this backlog:
  - SlideshowView.swift at 1,911 lines (up from 1,558 at sprint 1; threshold ~2,000)
  - 47+ hardcoded `NSNotification.Name("...")` string literals across SlideshowView + SlideyApp → issue #46
  - `MusicManager.swift` (343 lines) is a fully-shipped 5th source file not documented anywhere → issue #47
  - Session-state dictionaries at exactly 5 keys — at threshold but not over it; no action needed yet
- Parallelism: #46 and #47 can run simultaneously. Once #46 merges, #48 and #49 can run in parallel. #50 unblocks after #48 merges.
- Author trust filter: all issues filed by `josephclloyd` ✓.
