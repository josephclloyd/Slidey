---
name: project-sprint17-patterns
description: "Image edit compositing pipeline, key binding registry, HUD pattern, SwiftLint limits, CoreML conversion patterns — updated through Sprint 20 pre-sprint"
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

## Compositing pipeline order (fixed as of Sprint 18)

`updateDisplayImage` applies layers in this order:

1. Base image priority: `bgRemoved > faceRestored > redEye > upscaled > sharpened > smoothed > enhanced > original`
2. Flip (CIAffineTransform, horizontal then vertical)
3. Photo effect (CIFilter, cached in `effectImages[url]`)
4. Adjustments (Exposure/Highlights/Shadows/Vibrance/Warmth — skip during Adjustments HUD)
5. Vignette (CIVignetteEffect — skip during Vignette HUD, applied absolute last)

**How to apply:** Any new filter step must slot into this order in both `updateDisplayImage` and `setDisplay`. The HUD "skip" pattern (`!showXxxHUD` guard) prevents double-application during preview.

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

Keys bound as of Sprint 19:
`a`=enhance, `A`=remove-enhance, `m`=smooth, `M`=remove-smooth, `q`=denoise, `h`=sharpen, `H`=remove-sharpen, `u`=upscale-2x, `⌥U`=upscale-4x, `U`=remove-upscale, `s`=scale-to-native, `f`=scale-to-fill, `r`=rotate-CW, `R`=rotate-CCW, `n`=show-filename, `x`=favourite, `v`=favourites-only, `t`=thumbnails, `i`=image-info, `z`=smart-zoom, `/`=keyboard-shortcuts, `d`=debug-window, `j`=random-jump, `b`=before/after-preview, `e`=adjustments-hud, `c`=flip-horizontal, `C`=flip-vertical, `p`=face-restore, `P`=remove-face-restore, `g`=red-eye-removal, `G`=remove-red-eye, `k`=background-removal, `K`=restore-background.

Free slots: `l`, `o`, `w`, `y` (and uppercase variants of these).

SwiftLint `cyclomatic_complexity` error threshold is ~50. Run `xcodebuild | grep cyclomatic` after adding keys.

**Why:** `j` was missing from the registry in Sprint 17's memory — caused a key conflict when planning Sprint 18 (#167 initially proposed `j`). Always read the actual code, not just the registry.

---

## SlideshowView.swift size limits

As of Sprint 19 the file is ~3482 lines. `.swiftlint.yml` error threshold: 3500 (file) / 3000 (type body). The next substantial editing feature **must** extract content to a `SlideshowView+Edits.swift` extension before adding more code to the body. Change `@State private var` to `@State var` (internal) on anything the extension needs.

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
