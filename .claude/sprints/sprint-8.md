# Sprint 8 — 2026-06-09

Started: 2026-06-09T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 57 | Fix CLAUDE.md: Workflow section stale re: automated tests | CLAUDE.md | opus | — |
| 61 | Verify xcodebuild test surfaces as a separate CI check on PRs | `.github/workflows/*.yml` | opus | — |
| 66 | Extract SlideshowView into focused sub-components | `SlideshowView.swift`, new files | opus | — |
| 62 | Keyboard shortcut reference sheet (Help menu) | `SlideyApp.swift`, new file | opus | — |
| 64 | Copy file path to clipboard (Cmd+Shift+C) | `SlideshowView.swift`, `SlideyApp.swift` | opus | #66, #62 |

## Excluded

- #58 Expand SlideshowView tests — better written against the new extracted architecture; defer until after #66 merges
- #59 Expand SlideyApp tests — defer alongside #58
- #60 SwiftLint — could touch many source files to resolve violations; too broad to run alongside a large refactor (#66)
- #63 Persist zoom/pan — adds to SlideshowView while #66 is shrinking it; defer
- #65 Star/favourite images — same conflict as #63

## Notes

- Wave 1: #57 + #61 (parallel, no source conflicts)
- Wave 2: #66 + #62 (parallel: SlideshowView vs SlideyApp — no conflict)
- Wave 3: #64 (blocked by both #66 and #62; touches both files)
- #66 is pure extraction — impl session must not add features in the same PR
- Author trust filter: all issues filed by `josephclloyd` ✓.
