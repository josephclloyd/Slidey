# Sprint 31 — 2026-07-17

Started: 2026-07-17T14:41:37Z
Status: done

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

## Results

Released: v1.30 — 2026-07-17

### Shipped

- #282 Add RAW file support (CR2/NEF/ARW/DNG and 9 other extensions) — PR #294
- #283 Set as Desktop Picture applies to all displays on multi-monitor setups — PR #296
- #291 Overhaul README — document full current feature set and keyboard shortcuts — PR #295
- #284 Add VoiceOver accessibility to all editing HUD sliders and controls — PR #298
- #290 Unit tests for coordinate/mask-transform logic (ObjectRemoval, CropController, Y-axis conversions) — PR #297

### Incidents

- **Branch ordering**: Session for #290 (coordinate tests) accidentally branched from `desktop-picture-all-screens` instead of `main`, picked up a stale commit. Fixed via `git rebase --onto origin/main`.
- **FP precision**: Coordinate tests failed CI with `0.6000000000000001 != 0.6` (IEEE 754 `0.2 + 0.4`). Fixed by adding `assertPointEqual` helper with 1e-10 accuracy tolerance.
- **Impl session committed without running tests**: #290 impl session hit quota before verifying; orchestrator committed and pushed, tests failed on CI. Repaired directly.
- **PR bundle**: #291 impl session also added RAW extensions to `ImageLoader.swift`; repair dropped the bundled code change (RAW support was already in #282 by then).

### Stats

- PRs merged: 5 (all 5 sprint issues)
- Versions: 1.29 → 1.30
- CI wall time per PR: ~2–3 min
