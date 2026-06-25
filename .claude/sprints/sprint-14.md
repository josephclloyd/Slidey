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
