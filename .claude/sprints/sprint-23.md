# Sprint 23 — 2026-07-05

Started: 2026-07-05T00:00
Status: planned

## Theme: Discoverability + slideshow/export polish

Sprints 20-22 all shipped clean (no needs-attention exits), so this sprint stays at the
scaled-up 5-issue size introduced in Sprint 22 rather than stepping back down. No open
`meta`-labelled issues this cycle, so no between-sprint meta work is needed.

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 133 | Slideshow progress bar | SlideshowController.swift, SlideshowView.swift | opus | — |
| 137 | Drag current image out to Finder/other apps | SlideshowView.swift | opus | #133 |
| 206 | File menu items: real disabled state via @FocusedValue | SlideyApp.swift, SlideshowView.swift | opus | #137 |
| 209 | Align keyboard shortcuts to Apple/macOS standards (fullscreen, zoom) | SlideshowView.swift, SlideyApp.swift, KeyboardShortcutsView.swift, CLAUDE.md | opus | #206 |
| 102 | Export filtered/favourited image set to a folder | SlideyApp.swift, SlideshowView.swift, ImageLoader.swift | opus | #209 |

All five are serialized in one chain — every issue touches `SlideshowView.swift`, so per
plan.md's hot-file rule none can run in parallel. Ordered lowest-risk/most-additive first,
most-invasive last:

- **#133** is a pure addition (new controller-published progress value + an overlay bar) —
  no existing code path changes.
- **#137** adds a single `.onDrag` modifier to the image view; isolated, no interaction with
  existing gesture handling per the issue's own notes (must not break the unrelated `.onDrop`
  folder-import handler).
- **#206** is a mechanical sweep (`@FocusedValue` plumbing + `.disabled()` on existing menu
  items) but touches every File menu command in `SlideyApp.swift`, so it goes mid-chain
  before the more behavior-changing issues.
- **#209** changes existing Escape-key semantics (HIG fix: must stop entering full screen)
  and adds new View-menu items/bindings — behavior change, not just addition, and touches
  `KeyboardShortcutsView.swift` + `CLAUDE.md`'s key binding registry on top of the usual files.
- **#102** is the most involved: new File menu item, folder picker, bulk copy with
  progress/error toasts, reusing `imageLoader`'s active-filter state — placed last.

## Notes per issue

**#133 (Progress bar):** `SlideshowController` needs a published elapsed/normalised progress
value (~30fps timer, `(Date.now - lastAdvance) / interval`). SwiftUI overlay: a `Rectangle`
clipped to the progress fraction at the bottom edge of the image area, hidden when paused/
stopped. Must not collide with the existing filename/info overlays.

**#137 (Drag to Finder):** `.onDrag { NSItemProvider(contentsOf: url) }` on the image view.
Per the issue, edited images are session-only, so always drag the *original* file URL, not
a rendered/edited copy. Gate on `zoomScale == 1` (or a long-press threshold) so it doesn't
fight panning.

**#206 (File menu disabled state):** Expose "has current image" to the `Commands` structs via
`@FocusedValue` (SwiftUI's mechanism for focused-scene state → menu commands — `SlideyApp.swift`'s
`Commands` structs don't currently have `imageLoader` access). Wire `.disabled()` onto every
affected File menu item in one consistent pass — Rename, Move to Trash, Copy to Folder, Move
to Folder, Set as Desktop Picture (#204), Print (#205). Keep the existing no-op guards as a
safety net.

**#209 (Keyboard shortcut alignment):** Two independent HIG fixes bundled in one issue:
(1) Escape must only *exit* full screen / cancel an active HUD-crop-upscale — never *enter*
full screen; add `⌃⌘F` as the dedicated Enter/Exit Full Screen toggle with a View menu item.
(2) Add `⌘+`/`⌘-` "Zoom In"/"Zoom Out" View menu items as an alias alongside the existing bare
`+`/`-`/`=`/`_` (don't remove the bare keys — established rapid-browsing idiom here). Update
`KeyboardShortcutsView.swift` and `CLAUDE.md`'s key binding registry to match.

**#102 (Export filtered set):** "Currently visible" = `imageLoader.imageURLs` as filtered by
whatever filter is active (favourites, and now #100's ratings from Sprint 22) — same set the
thumbnail strip shows. `NSOpenPanel(canChooseDirectories: true)` for the destination (sandbox-
safe, user-picked). Reuse `showSavedToast`/`showErrorToast` patterns; continue past individual
copy failures rather than aborting the batch.

## Excluded (with reasons)

- **#135 Share current image via Share sheet** — still deferred per Joe's request (Sprint 22);
  no technical blocker, design notes (`NSSharingServicePicker`) unchanged.
- **#174 Copy/paste adjustments between images** — still stale per Sprint 22's finding: the
  issue's own `ImageAdjustments` struct name collides with the existing one from Sprint 18,
  and "the full edit state" now includes Sprint 21's `EditStack`/crop/flip/vignette layers the
  issue was never scoped against. Needs a fresh design pass against the current architecture
  before it's plannable — not attempted this sprint.
- **#169 Straighten (arbitrary-angle rotation)** — still deserves its own focused sprint
  (comparable scope to Sprint 21's crop feature, likely shared rotation math with
  `CropController`) rather than a quick-wins slot.
- **#138 Export current image with edits applied** — same staleness as #174: written before
  crop/`EditStack` existed, so "bake in the session edits" needs redefining against the current
  pipeline order (`editStacks[url]` → flip → effect → adjustments → vignette → crop) before
  it's actionable. Not paired with #137/#102 this time since it isn't ready — no reason to hold
  #137/#102 back for it.
- **#136 Trackpad swipe navigation** — still flagged as an interaction-risk item: two existing
  gesture-catcher layers (`ClickCatcherView`/`ZoomPanController`'s scroll-based pan, Sprint 21's
  `CropOverlayCatcher`) need careful design work against a new swipe gesture. Plan separately
  with focused attention, not bundled into a mixed batch.

## Key bindings

`⌃⌘F` (enter/exit full screen) and `⌘+`/`⌘-` (zoom, alias of existing bare `+`/`-`) are new
from #209 — both are menu-bar accelerators, not single-character bindings, so they don't
touch `handleCharacterKeyPress`'s registry directly. No other new bindings this sprint.

## Results

(filled in at review/retro time)
