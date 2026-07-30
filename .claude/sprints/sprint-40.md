# Sprint 40 — 2026-07-30

Started: 2026-07-30T00:00:00Z
Status: done

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 334 | Sprint 37 introspection fixes: extract upscale pipeline (finding #1, ~-300 lines SlideshowView.swift), fix reset-block gaps for grainReducedImages/grainReductionRawImages/objectRemovedImages (finding #3), add imageEffects asymmetry comment (finding #8) | SlideshowView.swift → SlideshowView+Upscale.swift | opus | — |
| 326 | Compare any two images (picker for right pane from directory) | SlideshowView+Compare.swift, SlideshowView.swift (minimal: comparePickerShowing state) | opus | #334 |
| 325 | Sync pan/zoom between compare panes | SlideshowView+Compare.swift, SlideshowView.swift (minimal: compareSyncEnabled flag) | opus | #326 |

## Excluded

- #329 Multi-select images for batch operations — large scope, own sprint
- #328 Selective colour — touches SlideshowView.swift; defer until #334 ships to clear file-length headroom

## Results

Released: v1.39 — 2026-07-30

### Shipped
- #334 Sprint 37 introspection fixes — extracted upscale pipeline to `SlideshowView+Upscale.swift` (-275 lines from SlideshowView.swift, now 3,104); fixed directory-reset gaps for `grainReducedImages`, `grainReductionRawImages`, `objectRemovedImages`; added `imageEffects` asymmetry comment. PR #349.
- #326 Compare any two images — sheet picker (thumbnail LazyVGrid) lets users choose any image from the current directory as the right compare pane; ⌥⇧B opens picker, existing ⌥B keeps direct-compare behaviour. PR #350.
- #325 Sync pan/zoom between compare panes — ⇧S toggles sync mode; `onChange` propagation with feedback-loop guard; no-jump on enable; auto-resets when compare mode exits. PR #351.

### Needs attention
(none)

### Stats
- PRs merged: 3 (#349, #350, #351)
- Total cost: ~$4.64 (impl $3.52, review $1.12)
- Repair rounds: 0
- CI wall time: ~2–2.5 min per PR

## Notes

- SlideshowView.swift at 3,379 lines (121 from SwiftLint file_length hard stop). #334 extracts upscale pipeline (~300 lines) to SlideshowView+Upscale.swift first, creating headroom for #326 and #325.
- Estimated SlideshowView.swift after sprint: 3,379 − 300 + ~60 ≈ 3,139 lines — safely below 3,500.
- All three issues are serialised through SlideshowView.swift (#334 → #326 → #325).
- #326 and #325 are paired compare features: #326 establishes picker infrastructure, #325 adds sync on the same ZoomPanController.
- #334 scope is limited to findings #1, #3, and #8 only — findings #2 (ImageSessionState refactor), #4 (key type inconsistency), #6 (HUD generic), #7 (semicolons) deferred as larger refactors.
