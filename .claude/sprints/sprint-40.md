# Sprint 40 — 2026-07-30

Started: 2026-07-30T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 334 | Sprint 37 introspection fixes: extract upscale pipeline (finding #1, ~-300 lines SlideshowView.swift), fix reset-block gaps for grainReducedImages/grainReductionRawImages/objectRemovedImages (finding #3), add imageEffects asymmetry comment (finding #8) | SlideshowView.swift → SlideshowView+Upscale.swift | opus | — |
| 326 | Compare any two images (picker for right pane from directory) | SlideshowView+Compare.swift, SlideshowView.swift (minimal: comparePickerShowing state) | opus | #334 |
| 325 | Sync pan/zoom between compare panes | SlideshowView+Compare.swift, SlideshowView.swift (minimal: compareSyncEnabled flag) | opus | #326 |

## Excluded

- #329 Multi-select images for batch operations — large scope, own sprint
- #328 Selective colour — touches SlideshowView.swift; defer until #334 ships to clear file-length headroom

## Notes

- SlideshowView.swift at 3,379 lines (121 from SwiftLint file_length hard stop). #334 extracts upscale pipeline (~300 lines) to SlideshowView+Upscale.swift first, creating headroom for #326 and #325.
- Estimated SlideshowView.swift after sprint: 3,379 − 300 + ~60 ≈ 3,139 lines — safely below 3,500.
- All three issues are serialised through SlideshowView.swift (#334 → #326 → #325).
- #326 and #325 are paired compare features: #326 establishes picker infrastructure, #325 adds sync on the same ZoomPanController.
- #334 scope is limited to findings #1, #3, and #8 only — findings #2 (ImageSessionState refactor), #4 (key type inconsistency), #6 (HUD generic), #7 (semicolons) deferred as larger refactors.
