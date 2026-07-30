# Sprint 39 — 2026-07-29

Started: 2026-07-29T00:00:00Z
Status: done

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 340 | Video: zoom and pan controls | SlideshowView+Video.swift (ZoomableContainerView wrap), SlideshowView.swift (minimal: route zoom keys to videoController when isVideoActive) | opus | — |
| 342 | Video: real-time brightness/contrast/gamma via AVVideoComposition | SlideshowView+Video.swift (HUD sliders + CIFilter chain on AVPlayerItem.videoComposition, per-URL state in VideoPlayerController) | opus | #340 |
| 341 | Video: capture current frame as image for editing | SlideshowView+Video.swift (Capture Frame button + AVAssetImageGenerator), SlideshowView.swift (setDisplay path wiring, synthetic URL keying), ImageLoader.swift (unit-testable extraction logic) | opus | #342 |

## Excluded

- #334 Sprint 37 introspection findings — memory-leak findings (#3 grainReducedImages not cleared, #5 unbounded caches) are worth fixing but tech debt; continue incremental approach
- #329 Multi-select — large scope, own sprint
- #328 Selective colour — touches SlideshowView.swift; next sprint
- #326 Compare any two images — touches SlideshowView.swift; next sprint
- #325 Sync pan/zoom between compare panes — touches SlideshowView.swift; next sprint

## Results

Released: v1.38 — 2026-07-30

### Shipped
- #340 Video: zoom and pan controls — `ZoomableContainerView` wrapping `AVPlayerView`, existing zoom keys (`s`, `f`, `z`, `⌘+`/`⌘-`, pinch, scroll, drag) routed to `VideoPlayerController.zoomPan` when video is active, per-URL state; 1 repair (missing `.onGeometryChange` on video path)
- #342 Video: real-time brightness/contrast/gamma via AVVideoComposition — CIColorControls + CIGammaAdjust chain on `AVPlayerItem.videoComposition`, HUD slider panel opened from video controls, per-URL `VideoAdjustments` state with Reset, session-only non-destructive
- #341 Video: capture current frame as image for editing — Capture Frame button in video HUD, `AVAssetImageGenerator` on background thread, synthetic URL (`?frame=N`) keying, routes through `setDisplay(base:for:)`, saves JPEG alongside video; unit tests for frame extraction and filename generation in `ImageLoaderTests`

### Needs attention
(none)

### Stats
- PRs merged: 3 (#344, #345, #346)
- Total cost: ~$11.64 (impl $9.78, review/repair $1.86)
- Repair rounds: 1 (#340 — missing `.onGeometryChange`)
- CI wall time: ~2–2.5 min per PR

## Notes

- SlideshowView.swift is at 3,379 lines (121 from SwiftLint hard stop). All three issues must minimise additions to SlideshowView.swift itself — video-specific logic stays in SlideshowView+Video.swift. #340 and #342 should add ≤20 lines each to SlideshowView.swift. #341 needs setDisplay wiring (~10 lines) but no new HUD state there.
- Serialisation order matters: #340 (adds zoom plumbing) → #342 (adds CIFilter composition, depends on VideoPlayerController from #340 being stable) → #341 (capture-frame uses the video state and routes through setDisplay). Each rebases on the merged predecessor.
- #341's synthetic-URL keying (`videoURL + "?frame=12.345"`) must integrate cleanly with the existing `[URL: …]` per-image state dictionaries — verify the synthetic URL doesn't collide with anything in ImageLoader's scan.
- All three: no new key bindings needed per CLAUDE.md registry; zoom keys are already routed, capture frame goes on a HUD button / menu item.
