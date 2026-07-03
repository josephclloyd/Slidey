# Sprint 21 — 2026-07-01

Started: 2026-07-01T18:45
Status: planned

## Theme: Crop feature, then compositing-pipeline rework

Two related issues, both touching `SlideshowView.swift`'s core display pipeline
(`updateDisplayImage()` / `setDisplay(base:for:)`). Full design context, architecture
rationale, and file/line citations are in the design plan written this session
(see `/Users/joe/.claude/plans/zazzy-riding-starfish.md` for the complete writeup this
sprint file summarizes).

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 168 | Crop: drag to select and crop region | SlideshowView.swift, new CropController.swift, new SlideshowView+Crop.swift, CLAUDE.md | opus | — |
| 198 | Photo edits should compose against the current image, not just pick highest-priority override | SlideshowView.swift, SlideshowView+AIEdits.swift, new EditStack.swift | opus | #168 |

**Sequencing (confirmed with Joe):** #168 ships first; #198 is `addBlockedBy: #168` and
starts only after #168 merges to main. This is the reverse of the design research's default
recommendation (which favored #198 first, since #168 is architecturally independent — crop
is a geometry "layer" like flip, not part of the priority-chain bug #198 fixes — and doing
#198 first would mean #168 builds against the final pipeline shape from day one). Joe chose
crop-first explicitly; because the two issues are serialized (not parallel), there's no
concurrent-edit conflict — #198's impl session's job includes verifying it does not regress
the just-shipped crop integration.

## Architecture summary

- `updateDisplayImage()` (`SlideshowView.swift:1675-1755`) and `setDisplay(base:for:)`
  (`:1877-1900`) do two things: (1) pick a base image from a buggy fixed-priority chain
  among 9 "content" edit dicts (this is the #198 bug), then (2) apply a sequential layer
  stack — flip → photo effect → adjustments → vignette — on top (this already works
  correctly today).
- Crop (#168) is a geometry operation like flip — it slots in as a 5th sequential layer
  (flip → photo effect → adjustments → vignette → **crop**), independent of the
  priority-chain rewrite.
- Confirmed workaround-in-the-wild: `invalidateUpscaling(for:)` (`SlideshowView.swift:2483-2487`,
  7 call sites) exists specifically to patch around the priority-chain bug by clearing the
  upscale cache whenever a lower-priority edit commits. #198 removes the need for it.

## Issue #168 — Crop

- **Key binding:** `w` to enter/toggle crop mode (confirmed with Joe — `c`/`C` are taken
  by flip since Sprint 17; only `w`/`W`/`y`/`Y` were free).
- **Gesture handling:** new `CropOverlayCatcher` (`NSViewRepresentable`), not an extension
  of the existing shared `ClickCatcherView` (`ZoomPanController.swift:145-177`) — swapped
  in via a `cropModeActive` flag on `ImageDisplayView` (`ZoomPanController.swift:181-227`).
  Pan/zoom/click-nav must be inert while crop mode is active.
- **Coordinate conversion:** invert the display transform chain (fit → rotate → scale →
  offset) to go from a drag point to a normalized (0-1, top-left origin, image-pixel
  space) `CGRect`. **Open risk:** the rotation-sign convention for this couldn't be
  determined by static analysis — verify empirically (rotate 90°, drag, confirm) during
  implementation.
- **Persistence:** new `CropRegion: Codable` (normalized `CGRect`), same
  `JSONEncoder`/`UserDefaults.data(forKey:)` pattern as `ImageAdjustments`
  (`SlideshowView.swift:115-125, 3117-3120, 3139-3141`), keyed by `url.absoluteString`.
- **File organization:** new `CropController` (plain Swift, coordinate math + drag state —
  unit-testable) + new `slidey/SlideshowView+Crop.swift` (SwiftUI overlay, gesture view,
  commit/cancel functions) — mirrors the `ZoomPanController`/`SlideshowView+AIEdits.swift`
  precedent. `SlideshowView.swift` has ~150 lines of headroom before the 3500-line
  SwiftLint error threshold; do not bump the threshold if this is exceeded — extract
  further instead (Sprint 20's retro flags threshold-bumping as a recurring failure mode).
- **HUD integration:** follow the existing Escape/Return-per-active-HUD pattern
  (`SlideshowView.swift:1076-1122`); guard entry with the other HUD flags for
  single-HUD-at-a-time. Shift-to-constrain-aspect-ratio read live via
  `NSEvent.modifierFlags.contains(.shift)` in the drag handler.
- **Testing:** extract `CropController`'s coordinate-conversion as a pure function, test
  it the same way `SlideyTests/SlideshowViewTests.swift` already tests
  `ZoomPanController`'s fit-scale math — cover a non-zero-rotation/zoom/pan case, corner
  min/max normalization after rotation, and the Shift-constrain math.

Full manual test checklist and CICrop/CIAffineTransform apply-order details: see the plan
doc.

## Issue #198 — Compositing rework

- **Approach:** full ordered-stack rewrite (`EditStack`/`EditStep`, new
  `slidey/EditStack.swift`), not a surgical patch — the current model is already propped
  up by scattered workarounds (`invalidateUpscaling`), the project's own memory
  (`.claude/memory/project-sprint17-patterns.md`) already flags this exact redesign as
  needed, and it also fixes a separate real bug: 6 of 9 content edits (upscale,
  faceRestore, redEye, bgRemove, artifactRemove, colorize) are currently session-only and
  silently lost on relaunch.
- **Data model:** `EditStack.steps: [EditStep]`, storing order + edit type only (not full
  replay parameters — replaying expensive CoreML steps from scratch would be a severe
  perf regression). Mirrors the existing enhance/smooth/sharpen lazy-recompute-on-load
  pattern, generalized to all 9 content edits.
- **Functions to change:** `updateDisplayImage()` (replace priority chain with stack
  walk), `setDisplay(base:for:)` (keep as sequential-layer application, base now means
  "current edit-stack composite"), every edit-commit function (append to stack before
  calling setDisplay), every `removeXxx()` (remove from stack, recomposite remaining chain
  from source), `loadFavourites()`/`saveFavourites()` (persist `editStacks`, retire the
  three marker `Set<String>` keys as a clean break — no migration needed, pre-1.0 internal
  state). `invalidateUpscaling` and its 7 call sites become removable once the stack model
  is verified equivalent.
- **Explicitly out of scope:** out-of-order edit reordering/partial-undo UI (never exposed
  to users); eager recompute of all AI edits on relaunch (only lazy, on-demand recompute
  of the currently-viewed image).
- **Testing:** extract `EditStack.append`/`remove`/ordering as pure, unit-testable logic
  (new `SlideyTests/EditStackTests.swift` or added to `SlideshowViewTests.swift`).
- **Must verify:** no regression to #168's crop integration (crop stays a layer applied
  after vignette, untouched by the priority-chain rewrite).

Full function-by-function change list and manual test checklist: see the plan doc.

## Excluded

None — sprint is intentionally scoped to these two related, sequenced issues given both
touch `SlideshowView.swift`'s core display pipeline.

## Notes

- `SlideshowView.swift` is at 3347 lines going into this sprint. SwiftLint error
  threshold is 3500 (file_length) / 3000 (type_body_length). Both issues add new
  extension files rather than inline code specifically to stay under this — do not repeat
  Sprint 20's mistake of bumping the threshold instead of extracting.
- Full research trail (2 Explore agents + 1 Plan/design agent, each independently
  verified against the actual source) and all open risks/questions for Joe are recorded
  in `/Users/joe/.claude/plans/zazzy-riding-starfish.md`.

## Results

Released: v1.20 — 2026-07-02

### Shipped
- #168 Crop: drag to select and crop region (`w` / `⇧W`) — new `CropController` (coordinate
  math, unit-tested) + `SlideshowView+Crop.swift`, normalized `CGRect` persistence, crop
  applied as the final geometry layer after vignette. PR #201, one repair round.
- #198 Photo edits now compose in the order applied instead of picking a single
  highest-priority winner — new `EditStack`/`EditStep` ordered model replaces the fixed
  priority chain in `updateDisplayImage()`. All 9 content edits (enhance, smooth, sharpen,
  upscale, faceRestore, redEye, bgRemove, artifactRemove, colorize) now persist order across
  navigation and relaunch (previously only enhance/smooth/sharpen survived relaunch). PR
  #202, shipped clean on the first review pass.

### Deviations from plan
- Sequencing: crop shipped first, then the compositing rework — the reverse of the design
  research's default recommendation, per Joe's explicit choice. No rework needed to crop as
  a result; the compositing rework's review confirmed crop's layer position was untouched.
- The `/implement` skill has no step to consult the sprint plan file — it only reads the raw
  GitHub issue body + CLAUDE.md. For both issues, the orchestrator proactively sent a
  follow-up message to the freshly-spawned impl session pointing it at `sprint-21.md`'s
  detailed design (key binding correction for #168, since the issue text said `c` but that
  conflicts with flip; the full `EditStack` data model and function-by-function change list
  for #198). Same gap applied to the default review prompt — the orchestrator manually
  augmented both review spawns with an explicit cross-check against the sprint plan's design
  decisions. This caught real deviations both times (see below). **Recommend promoting this
  into the `/implement` and review phase scripts** — see skill proposal in the diary.
- New source files (`CropController.swift`, `SlideshowView+Crop.swift`, `EditStack.swift`)
  are not auto-discovered by the build — `slidey/` is a traditional Xcode group (unlike
  `Resources/`, which is a `PBXFileSystemSynchronizedRootGroup`), so new files must be
  registered in `Slidey.xcodeproj/project.pbxproj` explicitly. Issue #168's impl session hit
  this as a build failure and needed a resumed-session fix; issue #198's session was
  pre-warned (via the orchestrator's redirect message) and got it right immediately.
- Both impl sessions and the #198 review session hit the usage quota mid-work multiple
  times. Two were zero-progress (discarded cleanly, re-spawned); two were partial-progress
  (resumed in place via `mcx claude send`, no work lost). One quota-status read showed a
  reset timestamp that had already passed while utilization was still reported at 100% —
  a real propagation lag, not a one-off; resolved itself within ~15 minutes on recheck.

### Review findings (both real, not false positives)
- #168: `windowTitle += " [cropped]"` accumulated on every `updateDisplayImage()` call
  instead of being set once (would have produced `image.jpg [cropped] [cropped] [cropped]`
  after repeated effect changes); a force-unwrap style nit; and a missing unit test for
  corner-point round-trip conversion at non-zero rotation — the exact risk the plan's
  testing section had flagged in advance.
- #198: none found by review — the sprint-plan cross-check (EditStack shape, function
  migration completeness, crop-regression check, out-of-scope-item absence, pbxproj
  registration, test coverage) all passed on the first pass.

### Needs attention
None — both issues merged clean.

### Stats
- PRs merged: 3 (#201, #202, plus this results/retro wrap-up)
- Repair rounds: 1 for #168 (real findings), 0 for #198
- CI wall time per PR: ~2–4.5 min
- Multiple quota-hit recoveries across both issues (see Deviations above) — no work lost
