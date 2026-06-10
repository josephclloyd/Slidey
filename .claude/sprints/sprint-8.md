# Sprint 8 — 2026-06-09

Started: 2026-06-09T00:00:00Z
Status: complete

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

## Results

Released: v1.8 — 2026-06-10

### Shipped
- #57 + #61 Fix CLAUDE.md + surface Test as a separate CI check — PR #68, merged 2026-06-09. Both issues addressed in one PR; Test job now appears as a distinct required check on every PR. Build + Test both green on rebase.
- #66 Extract SlideshowView sub-components — PR #70, merged 2026-06-10. `ZoomPanController.swift` (243 lines) and `SlideshowController.swift` (35 lines) extracted. SlideshowView.swift: 1,911 → 1,643 lines.
- #62 Keyboard shortcut reference sheet — PR #69, merged 2026-06-10. `KeyboardShortcutsView.swift` (94 lines) + Help menu item; all ~30 shortcuts listed by category, verified against actual bindings.
- #64 Copy file path to clipboard — PR #71, merged 2026-06-10. Cmd+Shift+C copies current image path; Edit > Copy File Path menu item; "Path copied to clipboard" toast.

### Stats
- PRs merged: 4 (#68–#71, covering 5 issues)
- Total cost: ~$7.47 (impl #57/#61 $1.00 + impl #66 $3.53 + impl #62 $1.32 + impl #64 $0.80 + reviews $0.82)
- CI wall time: ~2.5m per PR (Build + Test in parallel)
- Notable: #66 session hit usage quota mid-work ($3.53, left uncommitted changes); work was recovered manually — stash/rebase/conflict resolution. `Closes #N` missing from 1 of 4 PR bodies (#71). PR #69 needed a rebase after #70 merged (project.pbxproj conflict — both added new source files).
