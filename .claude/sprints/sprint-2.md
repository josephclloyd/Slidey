# Sprint 2 — 2026-05-27

Started: 2026-05-27T18:00:00Z
Status: complete

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 16 | Auto-open most recent directory at launch | `SlideshowView.swift`, `SlideyApp.swift`, `RecentDirectories.swift` | opus | — |
| 18 | Add unit tests where applicable | `ImageLoader.swift`, `RecentDirectories.swift`, `SlideyApp.swift` | opus | #16 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| — | — | Only 2 open issues from josephclloyd; all included. |

## Notes

- Sprint 2 — keeping at 2 issues (still early; scale after 3 clean sprints).
- #16 and #18 both touch `SlideyApp.swift` + `RecentDirectories.swift` → must serialize.
- #16 goes first: user-visible feature; #18 after merge so tests cover the completed codebase.
- #18 is non-trivial: adds a Xcode test target, evaluates what is unit-testable across 4 source files.
- Author trust filter: both issues by `josephclloyd`. ✓

## Results

Released: v1.2.0 — 2026-05-27

### Shipped
- #16 Auto-open most recent directory at launch — reopens the last-used folder on startup via security-scoped bookmark; shows welcome message on fresh install
- #18 Add unit tests where applicable — new SlideyTests target with 29 tests covering `AppSortOrder` enum properties, navigation index math, `removeImage` edge cases, `RecentDirectory` Codable roundtrips, and `PendingOpens` @Published behaviour

### Needs attention
(none)

### Stats
- PRs merged: 2 (#24, #25)
- Total cost: ~$2.82
- CI wall time per PR: ~57–70s
