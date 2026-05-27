# Sprint 1 — 2026-05-27

Started: 2026-05-27T00:00:00Z
Status: complete

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 17 | Update actions/checkout to Node.js 24-compatible version | `.github/workflows/build.yml` | opus | — |
| 14 | Prevent display sleep / screensaver while fullscreen | `SlideyApp.swift` | opus | — |
| 15 | Move to Trash key + Reveal in Finder | `SlideshowView.swift`, `SlideyApp.swift` | opus | #14 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| 16 | Auto-open most recent directory at launch | Shares `SlideshowView.swift` + `SlideyApp.swift` with #15; serializing both in the same sprint collapses to one active issue at a time. Deferred to Sprint 2. |

## Notes

- First sprint — starting with 3 issues per the "start small" guidance.
- #17 and #14 can run in parallel (different files).
- #15 blocked by #14 because both touch `SlideyApp.swift`.
- Author trust filter applied: all four open issues are by `josephclloyd`. ✓

## Results

Released: v1.1.0 — 2026-05-27

### Shipped
- #17 Update actions/checkout to v6 for Node.js 24 (CI infra) — PR #20
- #14 Prevent display sleep / screensaver while fullscreen (IOKit power assertion) — PR #21
- #15 Move to Trash (⌘⌫ / Delete) + Reveal in Finder (⌘R) — PR #22

### Needs attention
None — all planned issues merged.

### Stats
- PRs merged: 3
- Total cost: ~$2.94 ($0.45 + $1.26 + $1.23 across impl + review sessions)
- CI wall time per PR: ~76–90s
- Sprint elapsed: ~28 minutes
- Excluded: #16 (auto-open recent) deferred to Sprint 2
