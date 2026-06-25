# Sprint 14 — 2026-06-25

Started: 2026-06-25T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 108 | Investigate memory and performance with large directories (1000+ images) | ImageLoader.swift | opus | — |
| 109 | Add basic VoiceOver accessibility labels | SlideshowView.swift | opus | — |
| 101 | Presentation mode: hide cursor and menu bar when fullscreen | SlideshowView.swift, SlideyApp.swift | opus | #109 |

## Excluded

- #100 — Star/rate images: largest feature in backlog, touches SlideshowView + ImageLoader + SlideyApp; warrants its own sprint
- #102 — Export filtered set: touches SlideshowView.swift; sprint 15 candidate
- #105 — Undo trash/rename: touches SlideshowView.swift; sprint 15 candidate
- #108 investigation may reveal follow-on work filed as new issues

## Notes

- #108 (ImageLoader only) and #109 (SlideshowView only) touch distinct files — can run in parallel
- #101 blocked by #109: both touch SlideshowView.swift; #101 runs after #109 merges
- Author trust filter: all issues filed by `josephclloyd` ✓
- Sprint 13 shipped #118, #119, #120, #121; no sprint-13.md file was created (sprint ran before plan-file convention was enforced)

## Results

Released: v1.13 — 2026-06-25

### Shipped
- #109 Add basic VoiceOver accessibility labels (PR #123)
- #108 Debounce thumbnail generation for large directories (PR #124)
- #101 Presentation mode: hide cursor and menu bar when fullscreen (PR #125)

### Needs attention
None — all 3 planned issues shipped.

### Stats
- PRs merged: 3
- Total cost: ~$6.12
- Sessions spawned: 12 (3 impl @ opus, 4 review @ sonnet, 3 repair @ opus, 2 re-review @ sonnet)
- CI wall time per PR: ~90s average
- Notable: all three PRs needed a repair pass solely for missing testability note in PR description; baked into skill as a recurring pattern
