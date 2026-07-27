# Sprint 36 — 2026-07-27

Started: 2026-07-27T15:30:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 321 | Apply edits to active pane in compare mode | SlideshowView+Compare.swift (pane tap, highlight, compareActiveSide), SlideshowView.swift (editTargetURL computed var, state), SlideshowView+AIEdits.swift + other edit files (use editTargetURL) | opus | — |

## Excluded

(none — single-issue sprint)

## Notes

- `editTargetURL` must be a computed var on `SlideshowView` itself (NOT in an extension file, NOT private) — it needs to be readable from `SlideshowView+AIEdits.swift`, `SlideshowView+Crop.swift`, and any other extension that currently references `imageLoader.currentImageURL` directly for edit targeting.
- After an edit commits to the right pane via `setDisplay(base:for: compareURL)`, `compareImage` must be refreshed — it's a `@State var`, so the caller must update it from `effectImages[compareURL]` or `imageLoader.decodedImage(for: compareURL)`.
- `compareActiveSide` resets to `.left` on `exitCompareMode()`.
- Pane tap: add `onTapGesture` callback to `ComparePaneView` — do NOT make the tap gesture part of `ImageDisplayView` (it already handles click for navigation outside compare mode).
- Active pane indicator: a thin accent-colour border (`Color.accentColor.opacity(0.8)`, ~2pt) around the active pane is sufficient. Keep it subtle.
- Pure SwiftUI state + view wiring — no extractable unit test logic. PR description must state this explicitly.
