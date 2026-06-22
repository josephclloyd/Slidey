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

## Results

Released: v1.10.0 — 2026-06-22

### Shipped

- #79 Jump to random image — 'j' key jumps to a random image (or random favourite); KeyboardShortcutsView updated (PR #90)
- #82 Open single image file — File > Open now accepts image files in addition to folders; loads parent dir and jumps to the picked image (PR #91)
- #84 Slideshow loop on/off — "Loop slideshow" toggle in Settings (default on); when off, slideshow pauses at last image; manual nav always wraps (PR #92)
- #81 Rename current image — File > Rename… (Cmd+Shift+R); NSAlert prompt pre-filled with filename; ImageLoader.renameImage updates URL list and all per-URL state dicts in place (PR #93)

### Needs attention

None — 4/4 issues shipped.

### Stats

- PRs merged: 4 (#90, #91, #92, #93)
- Total cost: ~$5.57 (impl: $0.57 + $1.61 + $0.64 + $0.51 + $1.51; review: $0.19 + $0.30 + $0.20 + $0.22; orchestration)
- CI wall time per PR: ~2.5–3m
- Note: #81 hit 5h quota mid-session; resumed after window reset (~3.5h gap)
