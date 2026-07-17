# Sprint 31 — 2026-07-17

Started: 2026-07-17T14:41:37Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 291 | Overhaul README — stale feature docs | README.md | opus | — |
| 282 | Add RAW file support (CR2/NEF/ARW/DNG) | ImageLoader.swift | opus | — |
| 283 | Set as Desktop Picture — multi-monitor | SlideshowView.swift (setAsDesktopPicture only) | opus | — |
| 290 | Unit tests for coordinate/mask-transform logic | SlideyTests/ | opus | — |
| 284 | Accessibility (VoiceOver) gaps in newer editing HUDs | SlideshowView+Curves.swift, SlideshowView+Crop.swift, other HUD extensions | opus | — |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| 285 | Metadata/EXIF editing | Requires design decision (write to file vs export-only); large scope |
| 286 | Duplicate detection | New perceptual-hash subsystem + review UI; large scope |
| 287 | Side-by-side comparison | Heavy SlideshowView.swift layout change; design TBD |
| 288 | Search/filter bar | Hot file + new key binding; substantial scope |
| 289 | Video export | AVAssetWriter + progress HUD; substantial scope |

## Notes

- All 5 selected issues touch different files; no addBlockedBy edges required — can run in parallel.
- #283 edits a single isolated function (setAsDesktopPicture) in SlideshowView.swift; #284 edits HUD extension files (.+Curves, +Crop, etc.) — no overlap.
- #291's title still says "restore Roadmap/TODO section" (a stale artifact from filing) — the body is correct; impl session should note the title mismatch but address only the body's actual scope.
- #290 is high-priority: the codebase has hit the same Y-axis coordinate flip bug class 3 times; unit tests for the coordinate math are the mitigation.
