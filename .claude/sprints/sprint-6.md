# Sprint 6 — 2026-06-01

Started: 2026-06-01T19:07:00Z
Status: complete

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

## Results

Released: v1.6 — 2026-06-01

### Shipped
- #39 Copy image to clipboard — PR #44, merged 2026-06-01T19:15:51Z. Cmd+C copies the processed/enhanced image (upscaled > smoothed > enhanced > original priority chain, rotation baked in) to NSPasteboard. Edit > Copy Image menu item. Brief "Copied to clipboard" toast. NotificationCenter pattern followed.
- #38 Slideshow transitions — PR #45, merged 2026-06-01T19:34:36Z. Crossfade between images using `.id()` + `.transition(.opacity)` + `.animation(_:value:)`. Off by default, 0.3s duration, Settings toggle persisted via `@AppStorage`. Keyboard input non-blocking mid-fade.

### Stats
- PRs merged: 2 (#44, #45)
- Total cost: ~$2.27 (impl #39 $0.77 + impl #38 $1.13 + review #39 $0.21 + review #38 $0.26 + orchestration ~est.)
- CI wall time: ~2m per PR
- Notable: `Closes #N` missing from both PR bodies (added manually — routine step); main worktree drifted to feature branch after each impl session (expected, recovered with `git checkout main`)
