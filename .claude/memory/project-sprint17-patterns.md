---
name: project-sprint17-patterns
description: "HUD pattern, SwiftLint limits, CoreML conversion AND runtime gotchas (SwinIR trace size, ANE pre-compilation hang at both conversion and Swift runtime load), pbxproj file registration, coreView/overlayViews type-checker limits — updated through Sprint 26. Key binding registry and compositing pipeline order are NOT kept here — CLAUDE.md is authoritative for both, they change too often to duplicate."
metadata: 
  node_type: memory
  type: project
  originSessionId: d50fd14f-bc8a-4d35-981e-cd648fb3c1db
---

## `setDisplay(base:for:)` compositing helper

The canonical path for committing an edited NSImage in SlideshowView. It clears `effectImages[url]`, reapplies flip, photo effect, adjustments, and vignette in order, then sets `currentDisplayImage`. All edit features must route through it.

**Why:** Without routing through this helper, layers applied before an edit are silently lost after the edit commits.

**How to apply:** Any new image-editing feature that produces a new NSImage result must call `setDisplay(base: result, for: url)` as its final step, not `currentDisplayImage = result`.

---

## Compositing pipeline: two categories, not one flat list (concept stable since Sprint 21)

Rather than maintaining an enumerated order here (it has gone stale twice now — Sprint 25
added curves/straighten/perspective-correction/local-adjustments, Sprint 26 added AI
denoise — read `updateDisplayImage()` in `SlideshowView.swift` directly for the current
exact order), the durable pattern is the **two-category model** introduced in Sprint 21:

1. **`EditStack` walk** (`slidey/EditStack.swift`): `editStacks[url]` holds an ordered
   `[EditStep]` for "content" edits (enhance, smooth, sharpen, upscale, faceRestore,
   redEyeRemoval, backgroundRemoval, artifactRemoval, colorize, aiDenoise as of Sprint 26).
   `updateDisplayImage` walks steps in *applied* order (not fixed priority), threading each
   cached result forward, lazily recomputing only the first missing step.
   `EditStack.append()` moves a re-applied step to the end (toggle semantics);
   `remove(caseTag:)` drops a step and recomposites the rest from source. This replaced a
   fixed-priority "pick one winner" model (#198) that silently dropped lower-priority edits
   on re-render — do not resurrect that pattern.
2. **Everything else** (flip, photo effect, adjustments, curves, vignette, straighten,
   perspective correction, local adjustments, crop, and whatever's added next) is a
   fixed-position layer applied *after* the EditStack walk, each behind its own per-URL
   dict/state and each with a `!showXxxHUD` skip-during-preview guard.

**How to apply:** A new **content** edit (competes for stack order, like the 10 above)
becomes a new `EditStep` case, appended by its commit function and removed by its
`removeXxx()` — do not add a new dict + ad hoc fallback chain. A new **geometry/tone**
layer (doesn't compete for stack order, like curves or perspective correction) gets its own
fixed slot after the EditStack walk in both `updateDisplayImage` and `setDisplay` — read
the current function to find where to insert it, and update both the live-display path
*and* the export path (`SlideshowView+Export.swift`) and batch-apply/copy-paste paths
together, since Sprint 25/26 both found real bugs from these paths drifting out of sync
(#138's rotation-before-crop bug, #235's batch-apply missing straighten/denoise coverage).
`EditStack.append`/`remove` have unit tests in `SlideyTests/EditStackTests.swift` — extend
them for any new case.

---

## HUD pattern (Denoise, Vignette, Adjustments)

Consistent structure across all three HUDs:
1. `showXxxHUD = true` → `updateDisplayImage()` (now skips that layer) → snapshot `xxxBaseImage = currentDisplayImage`
2. Slider `onChange` → `scheduleXxxPreview()` (debounced 150ms Task)
3. Apply: store value in `xxxURLLevels[url]` → `saveFavourites()` → `showXxxHUD = false` → `updateDisplayImage()`
4. Cancel: `showXxxHUD = false` → `updateDisplayImage()` (restores persisted value)
5. Escape/Return handled in `handleKeyPress` before any other keys

**How to apply:** Copy this structure for any future intensity-slider HUD.

---

## Per-image persistence — REVERSED in Sprint 23 (#217/#218)

Session-only now, not persisted. Sprints 17-22 built up `UserDefaults`-backed persistence
for rotation, flip, vignette, adjustments, crop, and photo effect across launches; Sprint 23
explicitly reverted all of it (#217 "Stop persisting per-image edit stacks across app
restarts", #218 "Stop persisting rotation, flip, vignette, adjustments, crop, and photo
effect"). Every per-image edit is now purely in-memory `@State`, gone on relaunch. Do not
reintroduce cross-launch persistence for edit state without checking why it was removed
first — this was a deliberate product decision, not an oversight. (`saveFavourites()`/
`loadFavourites()` still persist favourites/ratings via `UserDefaults` — that's unrelated
and unaffected.)

---

## `handleCharacterKeyPress` key registry — see CLAUDE.md, not here

Do not duplicate the key list in this file — it changes almost every sprint and CLAUDE.md's
copy is the one that's actually kept current (every sprint's impl session updates it as
part of the PR). This file drifted out of sync with reality on this exact point twice
(Sprint 22 → 25 audit, Sprint 25 → 26 audit) — stop trying to maintain a second copy.

SwiftLint `cyclomatic_complexity` error threshold is ~50. Run `xcodebuild | grep cyclomatic`
after adding keys.

**Why this section exists at all:** `j` was missing from an early registry snapshot kept
here in Sprint 17's memory, causing a key conflict when planning Sprint 18 (#167 initially
proposed `j`, already taken). The lesson isn't "keep a better list" — it's **always read
`CLAUDE.md`'s registry directly at plan time, never rely on a memory-cached copy of it.**

---

## SlideshowView.swift size limits — extraction over threshold-bumping (updated Sprint 20)

As of Sprint 20 (post-extraction), `SlideshowView.swift` is 3304 lines; `.swiftlint.yml`
thresholds are back at the original 3500 (file) / 3000 (type body). AI-edit functions
(face restore, red-eye, background removal, artifact removal, colorization) live in
`slidey/SlideshowView+AIEdits.swift` (that's the actual extension name — not `+Edits.swift`).
Change `@State private var` to `@State var` (internal) and `private func` to `func` on
anything the extension needs.

**Why this matters — a recurring failure mode:** in Sprint 20, an impl session facing an
imminent threshold breach bumped `file_length`/`type_body_length` in `.swiftlint.yml`
(3500→3800, 3000→3200) instead of extracting, even though the sprint plan explicitly
predicted this exact scenario and called for extraction. It was caught in review and fixed
via a repair round. **When `SlideshowView.swift` is near 3500 lines and a new feature would
push it over: extract to `SlideshowView+AIEdits.swift`, do not raise the SwiftLint
thresholds.** Raising thresholds is a one-way ratchet — the next feature just re-breaches
the new, higher number.

---

## New Swift source files must be registered in project.pbxproj (recurring, Sprints 20-22)

`slidey/` is a **traditional Xcode group** with explicit `PBXFileReference` +
`PBXBuildFile` entries — unlike `Resources/`, which is a `PBXFileSystemSynchronizedRootGroup`
that auto-discovers new files. Any new `.swift` file added to `slidey/` (a new extension,
a new controller class, etc.) will compile fine in isolation but fail the full build with
"cannot find type/symbol in scope" until it's explicitly added to
`Slidey.xcodeproj/project.pbxproj`'s Sources build phase.

**Why this matters:** this has bitten an impl session in three sprints running — Sprint 20's
`SlideshowView+AIEdits.swift`, Sprint 21's `CropController.swift`/`SlideshowView+Crop.swift`/
`EditStack.swift`, and Sprint 22's `SlideshowView+Persistence.swift`/`SlideshowView+Rating.swift`
all needed this fix, sometimes discovered only after a build failure ate a repair cycle.
**When creating a new file under `slidey/`: immediately add matching `PBXFileReference` +
`PBXBuildFile` entries to `project.pbxproj`, following the pattern of an existing
recently-added file (e.g. search for `SlideshowView+Crop.swift`'s entries as a template) —
do not wait for the build to fail first.** In Sprint 22 this warning was included proactively
in the impl session's initial spawn message (rather than waiting for a build failure) and the
session got it right on the first attempt — that's the pattern to repeat going forward.

---

## `coreView`/`overlayViews` type-checker timeout is a *standing* risk, not per-feature (Sprint 22)

CLAUDE.md documents the Xcode 16.3 type-checker timeout gotcha ("unable to type-check this
expression in reasonable time") for `coreView`/`body`/`overlayViews`. As of Sprint 22, treat
this as **structurally near its limit at all times**, not just a risk for unusually complex
features. `coreView`'s modifier chain already had ~15 `.onChange` handlers before Sprint 22
started; adding even one small, simple one (`.onChange(of: minimumRatingFilter)`, from the
star-rating feature) was enough to tip it over.

**Two independent extraction targets, not one:**
1. `overlayViews`'s inline content (split into ~13 separate `@ViewBuilder private var`s in
   Sprint 22 — `imageInfoOverlay`, `thumbnailOverlay`, `filenameOverlay`, etc.)
2. `coreView`'s own **modifier chain length** (split into `coreViewBase` — ZStack + `.overlay`
   + `.onDrop` + roughly half the `.onChange` handlers — and `coreView`, which chains the
   remaining modifiers onto `coreViewBase`)

**Why this matters — misdiagnosis costs rounds:** in Sprint 22, the type-checker error's
reported line number shifts as earlier code shrinks, and it consistently points at `coreView`'s
`ZStack {` opening line regardless of whether the *actual* problem is inside the ZStack body
(`overlayViews`) or in the modifier chain *after* the ZStack. Extracting `overlayViews`
content alone was necessary but insufficient — the error persisted (at a shifted line) because
the modifier chain itself was still too long. **Do not assume the first extraction worked
just because the line number changed — recheck CI, and if it's still the same class of error,
read `coreView`'s full modifier chain directly to count `.onChange`/`.onReceive`/similar
calls before extracting further.** If a sprint plans any feature that adds a new modifier to
`coreView`, budget for a possible chain-split repair round, the same way `SlideshowView.swift`'s
file-length limit is already budgeted for.

---

## CoreML model integration pattern (Sprint 19)

For large CoreML models (>50 MB) in CI:
1. Track `weight.bin` via Git LFS: `git lfs track "**/*.mlpackage/Data/com.apple.CoreML/weights/weight.bin"` — **commit `.gitattributes` immediately to the feature branch**.
2. Add `lfs: true` to all `actions/checkout` steps in `build.yml` at the same time.
3. Use `MLModel(contentsOf:configuration:) + MLDictionaryFeatureProvider` instead of Xcode's auto-generated wrapper classes. Auto-generated classes require `coremlc` to compile the model at build time; the project file won't trigger this for models added via folder reference.

**Why:** The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` for `Resources/`, which does not reliably trigger `coremlc generate` for new mlpackage additions. Using the raw API removes the compile-time dependency entirely.

**Critical gotcha — ANE pre-compilation in `ct.convert()` (Sprint 20):**
Always pass `compute_units=ct.ComputeUnit.CPU_ONLY` to `ct.convert()`. Without it, `ct.convert()` internally loads the model via `MLModel(contentsOf:)` to validate it, triggering Apple Neural Engine compilation via XPC — which blocks the conversion for 60+ minutes. `CPU_ONLY` skips this at conversion time.

**Correction (Sprint 26, #247) — this ALSO happens at Swift runtime, not just conversion.** The line above previously said the saved `.mlpackage` "can still be loaded with GPU/ANE compute units at Swift runtime" — that turned out to be wrong for SwinIR specifically. Requesting `.all` compute units in `MLModelConfiguration` when loading the model in the app (not just during Python-side conversion) triggered the identical `ANECompilerService.xpc` stall, observed directly at 100% CPU for 130+ minutes with no way to cancel from app code. Fixed by using `.cpuAndGPU` at Swift runtime too, not just `CPU_ONLY` at conversion time. See CLAUDE.md's Gotchas section for the full runtime-side writeup (timeout/cancellation limitations, the orphaned-process caveat). **Do not assume the conversion-time-only framing above is still accurate — verify against CLAUDE.md before trusting either compute-units claim.**

**SwinIR-specific — trace at native training size only:**
SwinIR must be traced at exactly `img_size=126` (126×126) — the model's training patch size. Other sizes (128, 256, 512) either OOM during trace (≥256) or trigger a coremltools `slice_by_index` error in the shift-mask computation (128). The 126×126 input requires tiling at Swift inference time.
