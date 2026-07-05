---
name: project-sprint17-patterns
description: "Image edit compositing pipeline (EditStack model), key binding registry, HUD pattern, SwiftLint limits, CoreML conversion patterns, pbxproj file registration, coreView/overlayViews type-checker limits — updated through Sprint 22"
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

## Compositing pipeline order (rewritten Sprint 21 — EditStack model)

`updateDisplayImage` applies layers in this order:

1. **Base image = `EditStack` walk** (`slidey/EditStack.swift`): `editStacks[url]` holds an
   ordered `[EditStep]` (enhance, smooth(noiseLevel:), sharpen, upscale(factor:), faceRestore,
   redEyeRemoval, backgroundRemoval, artifactRemoval, colorize). `updateDisplayImage` walks
   the steps in the order they were *applied* (not a fixed priority), threading each step's
   cached result forward as the input to the next, lazily recomputing only the first missing
   step. `EditStack.append()` moves a re-applied step to the end (toggle semantics);
   `remove(caseTag:)` drops a step and the remaining chain recomposites from source in order.
   This replaced a fixed-priority "pick one winner" model (#198) that silently dropped
   lower-priority edits on any re-render — see git history pre-#202 if you need the old
   version for reference, do not resurrect the pattern.
2. Flip (CIAffineTransform, horizontal then vertical)
3. Photo effect (CIFilter, cached in `effectImages[url]`)
4. Adjustments (Exposure/Highlights/Shadows/Vibrance/Warmth — skip during Adjustments HUD)
5. Vignette (CIVignetteEffect — skip during Vignette HUD)
6. Crop (`CropRegion`, normalized `CGRect` — added Sprint 21, applied as the final geometry
   layer, after vignette)

**How to apply:** Any new filter/geometry step that should compose with everything else
(not itself a "content" edit competing for stack order) slots in after step 1, in both
`updateDisplayImage` and `setDisplay`. A new *content* edit (like the 9 above) becomes a new
`EditStep` case and must be appended to `editStacks[url]` by its commit function and removed
by its `removeXxx()` function — do not add a new dict + ad hoc fallback-chain pattern, that's
exactly what #198 replaced. `EditStack.append`/`remove` have unit tests in
`SlideyTests/EditStackTests.swift` — extend them for any new case.

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

## Per-image persistence

- Single `Double` per image: `[String: Double]` in UserDefaults (vignette, denoise)
- Multi-value per image: `Codable` struct → `JSONEncoder` → `UserDefaults.data(forKey:)` (adjustments)
- All persisted in `saveFavourites()` / `loadFavourites()`

---

## `handleCharacterKeyPress` key registry

Keys bound as of Sprint 22:
`a`=enhance, `A`=remove-enhance, `m`=smooth, `M`=remove-smooth, `q`=denoise, `h`=sharpen, `H`=remove-sharpen, `u`=upscale-2x, `⌥U`=upscale-4x, `U`=remove-upscale, `s`=scale-to-native, `f`=scale-to-fill, `r`=rotate-CW, `R`=rotate-CCW, `n`=show-filename, `x`=favourite, `v`=favourites-only, `t`=thumbnails, `i`=image-info, `z`=smart-zoom, `/`=keyboard-shortcuts, `d`=debug-window, `j`=random-jump, `b`=before/after-preview, `e`=adjustments-hud, `c`=flip-horizontal, `C`=flip-vertical, `p`=face-restore, `P`=remove-face-restore, `g`=red-eye-removal, `G`=remove-red-eye, `k`=background-removal, `K`=restore-background, `l`=artifact-removal, `L`=restore-artifacts, `o`=colorize, `O`=remove-colorization, `w`=crop, `W`=remove-crop, `0`=clear-rating, `1`-`5`=set-rating.

Free slots: `y`/`Y` only. Digits `6`-`9` are also free (only `0`-`5` are used, per the 0-5 star rating scale).

SwiftLint `cyclomatic_complexity` error threshold is ~50. Run `xcodebuild | grep cyclomatic` after adding keys.

**Why:** `j` was missing from the registry in Sprint 17's memory — caused a key conflict when planning Sprint 18 (#167 initially proposed `j`). Always read the actual code, not just the registry.

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
Always pass `compute_units=ct.ComputeUnit.CPU_ONLY` to `ct.convert()`. Without it, `ct.convert()` internally loads the model via `MLModel(contentsOf:)` to validate it, triggering Apple Neural Engine compilation via XPC — which blocks the conversion for 60+ minutes. `CPU_ONLY` skips this; the saved `.mlpackage` can still be loaded with GPU/ANE compute units at Swift runtime. The MIL program in the package is hardware-agnostic regardless of the `compute_units` flag used during conversion.

**SwinIR-specific — trace at native training size only:**
SwinIR must be traced at exactly `img_size=126` (126×126) — the model's training patch size. Other sizes (128, 256, 512) either OOM during trace (≥256) or trigger a coremltools `slice_by_index` error in the shift-mask computation (128). The 126×126 input requires tiling at Swift inference time.
