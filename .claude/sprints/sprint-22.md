# Sprint 22 — 2026-07-04

Started: 2026-07-04T00:00
Status: planned

## Theme: Quick wins (system integration + slideshow polish)

After two heavier sprints (Sprint 20: AI/ML models, Sprint 21: crop + compositing rework),
this sprint batches smaller, well-isolated backlog items: macOS system integration
(print, share, desktop picture) plus two slideshow/rating features. Sizing up from the
recent 2-issue sprints to 5, per the "scale after clean sprints" guidance — most of these
are small and low-risk.

## Pre-sprint backlog hygiene

Three open issues were confirmed already shipped in earlier sprints but never auto-closed
(pre-dating this project's "Closes #N" convention, or a straight duplicate) — closed during
planning, not part of this sprint:
- #167 (Adjustments HUD) — shipped in #185
- #171 (Vignette effect) — shipped in #184
- #134 (Keyboard shortcut help overlay) — duplicate of #62, shipped in #69

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 129 | Set current image as Desktop Picture | SlideyApp.swift, SlideshowView.swift, Notifications.swift | opus | — |
| 139 | Print current image (Cmd+P) | SlideyApp.swift, SlideshowView.swift, Notifications.swift | opus | #129 |
| 141 | True shuffle mode for auto-advance | SlideshowController.swift, SlideyApp.swift, SlideshowView.swift (minimal) | opus | #139 |
| 100 | Star/rate current image (1–5 keys, EXIF rating) | SlideshowView.swift, ImageLoader.swift | opus | #141 |

All four are serialized in one chain — per plan.md's hot-file rule, any two issues that both
add to `SlideshowView.swift` conflict if run in parallel, and all four touch it (#129/#139
each add a small `NotificationCenter` receiver to the `.onReceive` chain in `body`; #141
touches it minimally if at all — kept in the chain for safety on this first larger-batch
sprint; #100 is the most invasive, placed last).

## Notes per issue

**#129 (Desktop Picture):** `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` with
`NSScreen.main`. No new entitlements needed. Trivial — File menu item + one `.onReceive`.

**#139 (Print):** `NSPrintOperation.run()` on a temporary `NSImageView` configured with the
current `NSImage`. Standard macOS print dialog handles page sizing.

**#141 (Shuffle):** Fisher-Yates shuffle queue — a `[URL]` array seeded from
`imageLoader.imageURLs.shuffled()`, drained one URL per advance, refilled when empty. This is
exactly the kind of logic `SlideshowController.swift` already holds (extracted in Sprint 15)
and is unit-testable — add tests there, following the existing loop-on/off test pattern.
Toggle via `Slideshow > Shuffle on Advance`, persisted `@AppStorage`, off by default.

**#100 (Star/rate):** No EXIF *write* precedent exists yet in this codebase —
`ImageLoader.swift` only reads EXIF (capture date, via `CGImageSourceCopyPropertiesAtIndex`).
Writing the XMP `xmp:Rating` tag needs `CGImageDestinationCreateWithURL` +
`CGImageDestinationAddImageFromSource` (with a modified properties dict) +
`CGImageDestinationFinalize`, establishing a new pattern — this is the first feature in the
app that writes to the *original* file rather than staying session-only, which is intentional
per the issue's acceptance criteria but worth calling out explicitly in the PR description
since it's a new category of side effect for this app. Digit keys `0`-`5` are confirmed free
in the key registry. Star indicator goes in the image info overlay (`overlayViews` section —
watch the type-checker line-count gotcha). "Filter by rating" sits alongside the existing
favourites filter.

## Excluded (with reasons)

- **#135 Share current image via Share sheet** — skipped for this sprint per Joe's request.
  No technical blocker; the design notes above (`NSSharingServicePicker`) still apply
  whenever it's picked back up.
- **#174 Copy/paste adjustments between images** — the issue's own implementation notes
  propose a new `struct ImageAdjustments: Codable` that collides by name with the
  **existing** `ImageAdjustments` struct (exposure/highlights/shadows/vibrance/warmth,
  Sprint 18). Worse, the issue was written before Sprint 21's `EditStack` rework and crop
  feature — "the full edit state" it wants to snapshot now includes `editStacks[url]`, crop,
  flip, and the vignette/adjustments layers, not the old fixed-priority model it was scoped
  against. Needs a fresh look at what "copy the edit state" means against the current
  architecture before it's actionable — defer to a future sprint, planned fresh.
- **#169 Straighten (arbitrary-angle rotation)** — a full new HUD following the established
  Denoise/Vignette/Adjustments/Crop pattern (its own `showStraightenHUD`, live preview,
  Return/Escape). Comparable scope to Sprint 21's crop feature, including likely reuse of
  `CropController`'s rotation math. Deserves its own focused sprint rather than being bundled
  into a quick-wins batch — plan separately, considering whether to extract shared rotation
  math between crop and straighten.
- **#138 Export current image with edits applied** — same staleness issue as #174: written
  before crop/EditStack existed, so "bake in the session edits" needs to be redefined against
  the current pipeline (walk `editStacks[url]`, then flip → effect → adjustments → vignette
  → crop, matching `updateDisplayImage`'s current order) rather than the old
  enhance/smooth/rotation-only description in the issue text.
- **#137 Drag current image out to Finder** — small and isolated on its own, but thematically
  pairs with #138/#102 (all "get an image out of Slidey"). Deferred to keep this sprint's
  theme (isolated system-integration + slideshow polish) coherent rather than growing to 8
  issues; plan alongside #138/#102 in a future "export" themed sprint.
- **#136 Trackpad swipe navigation** — flagged interaction risk: the existing pan mechanism
  already uses trackpad scroll (`ClickCatcherView.scrollWheel`, `ZoomPanController.swift`),
  and Sprint 21's crop feature added a second gesture-catcher layer
  (`CropOverlayCatcher`). A new swipe-navigation gesture needs careful design against both of
  those, similar to the multi-agent research crop got — not a quick win, plan separately.
- **#102 Export filtered/favourited image set to a folder** — grouped with #137/#138 for a
  future export-themed sprint (see above).

## Key bindings

`0`–`5` for rating (issue #100's own spec). No new single-letter bindings needed for the
other four issues (menu-only or existing-key-adjacent). Confirmed `0`-`5` are unused in the
current `handleCharacterKeyPress` registry.
