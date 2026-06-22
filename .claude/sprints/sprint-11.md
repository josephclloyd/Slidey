# Sprint 11 — 2026-06-22

Started: 2026-06-22T14:56:27Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 82 | Open a single image file (not just a folder) | SlideyApp.swift | opus | — |
| 79 | Jump to random image ('j' key) | SlideshowView.swift, KeyboardShortcutsView.swift | opus | — |
| 84 | Slideshow loop on/off setting | SlideshowView.swift, SlideshowController.swift | opus | #79 |
| 81 | Rename current image file | SlideshowView.swift, ImageLoader.swift | opus | #84 |

## Excluded

- #83 (Copy or move current image to another folder) — most complex of the backlog; involves two new menu items, NSOpenPanel, toast confirmation, and reusing the move-to-trash removal path. Sprint 12 candidate.

## Notes

- Wave 1 (parallel): #82 + #79 — no file conflicts (#82 is SlideyApp.swift only)
- #84 blocked by #79: both touch SlideshowView.swift
- #81 blocked by #84: both touch SlideshowView.swift
- #79 is a one-liner in handleKeyPress + a KeyboardShortcutsView.swift entry; small but must merge before the SlideshowView.swift chain starts
- Author trust filter: all issues filed by `josephclloyd` ✓
