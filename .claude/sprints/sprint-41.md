# Sprint 41 — 2026-07-31

Started: 2026-07-31T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 328 | Selective colour: desaturate all except chosen hue | SlideshowView.swift, SlideshowView+AIEdits.swift (or new extension) | opus | — |
| 329 | Multi-select images for batch operations | SlideshowView.swift, ImageLoader.swift | opus | #328 |

## Excluded

(none — only 2 open issues in backlog)

## Notes

- Both issues touch `SlideshowView.swift`, so serialized: #328 first, #329 after it merges and rebases.
- #328 is a Core Image colour effect with a HUD slider — contained scope. Key binding slot needed; must check CLAUDE.md registry before picking a key.
- #329 is a larger interaction mode (selection state, thumbnail highlights, batch actions, trash). References `trashItem` logic that may or may not already exist from a prior sprint (#329 body mentions it but it's unclear if #329 was the original trash issue — verify at impl time).
- No meta issues in backlog.
