# Sprint 5 — 2026-05-30

Started: 2026-05-30T14:34:10Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 36 | Music settings (persist + auto-start) | `SlideshowView.swift`, `SlideyApp.swift`, `MusicManager.swift` | opus | — |
| 37 | EXIF/image info overlay | `SlideshowView.swift`, `ImageLoader.swift` | opus | #36 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| 38 | Slideshow transitions | Deferred to future sprint |
| 39 | Copy image to clipboard | Deferred to future sprint |

## Notes

- #36 and #37 both touch `SlideshowView.swift` — serialized, #37 blocked by #36.
- #36 adds settings persistence for music mode and auto-start behavior; touches `MusicManager.swift` (state restore) and `SlideyApp.swift` (Settings scene).
- #37 adds an 'i' key info overlay reading EXIF via `CGImageSource`; `ImageLoader.swift` may need a helper to extract metadata, or it can be done inline in `SlideshowView.swift`.
- Author trust filter: #36 filed by `josephclloyd` ✓; #37 drafted and filed this session per Joe's instruction ✓.
