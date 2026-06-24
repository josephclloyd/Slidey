# Sprint 13 — 2026-06-24

Started: 2026-06-24T14:10:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 97 | Add test coverage report to CI | .github/workflows/ci.yml | opus | — |
| 99 | Add PR size warning for large diffs | .github/workflows/pr-size.yml (new) | opus | — |
| 103 | Sort by EXIF capture date | ImageLoader.swift, SlideyApp.swift | opus | — |
| 106 | Show image dimensions in window title | SlideshowView.swift | opus | — |
| 104 | Improve rename UX when target filename already exists | SlideshowView.swift | opus | #106 |

## Excluded

- #109 VoiceOver accessibility — extensive SlideshowView.swift changes; Sprint 14 candidate
- #108 Large directory performance — investigation, needs profiling session; Sprint 14 candidate
- #105 Undo Move to Trash and Rename — complex NSUndoManager integration; Sprint 14 candidate
- #101 Presentation mode — enhancement, SlideshowView.swift; Sprint 14 candidate
- #102 Export filtered set — enhancement, SlideshowView.swift + SlideyApp.swift; Sprint 14 candidate
- #100 Star/rate images — large feature, warrants its own sprint

## Notes

- #97 and #99 both touch CI only — parallel-safe (#99 uses a new pr-size.yml, no ci.yml conflict)
- #103 is ImageLoader-primary; sort menu uses @AppStorage("sortOrder") so no SlideshowView.swift changes expected
- #106 and #104 both touch SlideshowView.swift — #104 blocked by #106
- #97, #99, #103, #106 can all start in parallel; #104 starts after #106 merges
- Author trust filter: all issues filed by `josephclloyd` ✓
