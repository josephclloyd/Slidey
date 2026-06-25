# Sprint 15 — 2026-06-25

Started: 2026-06-25T20:15:23Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 142 | Music autostarts ignoring Resume music setting | MusicManager.swift, SlideshowView.swift | opus | — |
| 143 | Slideshow should not auto-start on launch | SlideshowView.swift | opus | #142 |
| 126 | Add 2x and 4x AI upscale options with separate keys | SlideshowView.swift, SlideyApp.swift | opus | #143 |
| 105 | Undo support for Move to Trash and Rename | SlideshowView.swift, SlideyApp.swift | opus | #126 |

## Excluded

- #102 — Export filtered set: sprint 16 candidate
- #100 — Star/rate images: EXIF writing is complex, warrants its own sprint
- #129–#141 — New issues filed this session: sprint 16+

## Notes

- All 4 issues touch SlideshowView.swift — serialized via blocked-by chain
- Bugs (#142, #143) run first; enhancements follow after fixes are merged
- #142 primarily touches MusicManager.swift; only two call sites in SlideshowView.swift need updating
- Scaling to 4 issues this sprint (sprint 14 shipped 3 cleanly; backlog now healthy)
- Author trust filter: all issues filed by josephclloyd ✓
- Closed duplicate #132 (identical to #130, filed twice due to shell escaping error)
