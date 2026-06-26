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

## Results

Released: v1.14 — 2026-06-26

### Shipped
- #142 Fix music autoplaying regardless of Resume music setting (PR #145) — 1 repair pass
- #143 Ensure slideshow never auto-starts on launch (PR #146)
- #126 Add 2x and 4x AI upscale options with separate keys (PR #147, 5 new tests)
- #105 Add Cmd+Z undo for Move to Trash and Rename (PR #148)

### Needs attention
- #149 (filed post-sprint): 2x upscale produces corrupted/jumbled output — regression from #126; sprint 16 candidate

### Stats
- PRs merged: 4
- Total cost: ~$10.70
- Sessions spawned: 12 (4 impl @ opus, 4 review @ sonnet, 1 repair @ opus, 1 re-review @ sonnet, 2 wasted on quota hits)
- Quota hits: 2 (both on first impl attempt for #126 and #105; zero-progress cases, re-spawned clean after reset)
- Notable: #142 repair fixed a deeper design issue — activate() calls removed entirely from directory-open and fullscreen handlers, not just gated; music now only starts via toggleSlideshow()
