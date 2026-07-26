# Sprint 34 — 2026-07-23

Started: 2026-07-23T17:15:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 309 | Before/after drag slider | SlideshowView.swift (key binding, state), SlideshowView+BeforeAfterSlider.swift (new) | opus | — |
| 307 | Histogram overlay | SlideshowView.swift (key binding), SlideshowView+Histogram.swift (new) | opus | #309 |
| 308 | Animated GIF / APNG playback | ImageLoader.swift (detection, frame loading), SlideshowView.swift (animation timer) | opus | #307 |

## Excluded

- #312 Grid / contact sheet view — deferred to Sprint 35; large scope
- #313 Saved filter presets — deferred to Sprint 35; builds on #288

## Results

Released: v1.33 — 2026-07-25

### Shipped
- #309 Before/after drag slider (⇧B) — draggable reveal divider with clipShape mask; repair: fixed ⇧B routing through compare mode handler, fixed menu label "(B)" → "(⇧B)"
- #307 Histogram overlay (⌥H) — SwiftUI Canvas RGB+luminosity chart, per-image session state, 3 unit tests; repair: added refreshHistogramOverlay() to early-return path in updateDisplayImage()
- #308 Animated GIF/APNG playback — SlideshowView+Animation.swift, off-thread frame decode, per-frame UnclampedDelayTime with 0.1s minimum, slideshow pause during animation, unit tests

### Needs attention
(none)

### Stats
- PRs merged: 3 (#315, #316, #317)
- Total cost: ~$7.90 (impl: $1.92 + $2.25 + $2.71, review/repair: ~$1.02)
- Review rounds: 1 repair each for #309 and #307; #308 clean on first pass
- CI wall time per PR: ~2.5 min

## Notes

- All three issues touch `SlideshowView.swift` → fully serialized: #309 → #307 → #308.
- **#309 baseline**: `SlideshowView+Compare.swift` is the pattern — `clipShape` mask + `DragGesture` instead of two panes. Key `b` is currently a full toggle; slider mode should complement it (e.g. hold or separate key).
- **#307 baseline**: Compute histogram from `currentDisplayImage` CGImage bitmap. Draw with SwiftUI `Canvas`. Must respect post-edit image state. Check CLAUDE.md key registry before picking a binding.
- **#308 baseline**: `CGImageSourceGetCount > 1` detects animation. Per-frame delay via `kCGImagePropertyGIFDelayTime` / `kCGImagePropertyAPNGDelayTime`. Frame decoding off main thread. Slideshow auto-advance pauses during animation. `setDisplay(base:for:)` remains the commit path.
