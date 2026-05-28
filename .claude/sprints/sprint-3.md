# Sprint 3 — 2026-05-28

Started: 2026-05-28T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 26 | Auto-open recent: show loading state instead of directory picker while images load | `SlideshowView.swift`, `ImageLoader.swift` | opus | — |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| — | — | Only 1 open issue from josephclloyd; all included. |

## Notes

- Single-issue sprint — no parallelism or serialization needed.
- `ImageLoader.swift` likely needs a `isLoading` / progressive-first-image state exposed so `SlideshowView` can branch on it.
- Preferred impl: progressive render (show first decoded image immediately, remaining load in background). Fallback: spinner on black if scan must complete before any image is available.
- Welcome screen must never appear during auto-open path.
- Author trust filter: #26 filed by `josephclloyd`. ✓
