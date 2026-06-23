# Sprint 12 — 2026-06-23

Started: 2026-06-23T12:52:42Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 94 | Add SlideshowController tests for loop on/off | SlideshowControllerTests.swift (new) | opus | — |
| 96 | Expand ImageLoader test coverage for renameImage | ImageLoaderTests.swift | opus | — |
| 98 | Decouple CI from hardcoded Xcode version | .github/workflows/ci.yml | opus | — |
| 107 | Detect and surface error when watched directory is moved or renamed | ImageLoader.swift | opus | — |
| 95 | Copy or move current image to another folder | SlideshowView.swift, SlideyApp.swift | opus | — |

## Excluded

- #83 — duplicate of #95 (identical title/body); recommend closing as duplicate
- #106 Window title dimensions — polish; Sprint 13 candidate
- #103 Sort by EXIF capture date — enhancement; Sprint 13 candidate (ImageLoader.swift already touched by #107)
- #97 Coverage report in CI — ci-cd; follow-on after #98 lands
- #99 PR size warning — ci-cd; Sprint 13 candidate
- #100 Star/rate images — large feature, warrants its own sprint
- #104 Rename UX validation — polish; Sprint 13 candidate
- #105 Undo trash/rename — polish; Sprint 13 candidate
- #101 Presentation mode — enhancement; Sprint 13 candidate
- #102 Export filtered set — enhancement; Sprint 13 candidate
- #109 VoiceOver accessibility — accessibility; Sprint 13 candidate
- #108 Large dir performance — investigation; needs profiling session

## Notes

- All 5 issues touch distinct files — no merge conflicts; all can run in parallel
- Sprint 11 deferred #83/#95 ("copy/move to folder") explicitly; this sprint delivers it
- Author trust filter: all issues filed by `josephclloyd` ✓
