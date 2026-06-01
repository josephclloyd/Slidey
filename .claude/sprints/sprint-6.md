# Sprint 6 — 2026-06-01

Started: 2026-06-01T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 39 | Copy image to clipboard | `SlideshowView.swift`, `SlideyApp.swift` | opus | — |
| 38 | Slideshow transitions | `SlideshowView.swift`, `SlideyApp.swift` | opus | #39 |

## Excluded

(none — backlog is fully included)

## Notes

- #39 and #38 both touch `SlideshowView.swift` — serialized; #38 blocked by #39.
- #39: Cmd+C copies the visible (processed/enhanced) image to NSPasteboard. Needs to render what the user sees (rotated, smoothed, enhanced) rather than raw bytes. Menu item under Edit > Copy Image. Key handling in `SlideshowView.swift`, menu wiring in `SlideyApp.swift`.
- #38: Crossfade transition between images, off by default. Settings toggle + configurable duration. Must not block keyboard input mid-fade. Both windowed and fullscreen. Settings in `SlideyApp.swift`, animation logic in `SlideshowView.swift`.
- Author trust filter: both issues filed by `josephclloyd` ✓.
- Both were deferred from Sprint 5 — no new surprises expected.
