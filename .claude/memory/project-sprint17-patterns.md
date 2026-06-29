---
name: project-sprint17-patterns
description: "Image edit compositing pipeline, key binding registry, HUD pattern, and SwiftLint limits — updated through Sprint 18"
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

`updateDisplayImage` and `setDisplay(base:for:)` apply layers in this order:

1. Base image (upscaled > sharpened > smoothed > enhanced > original)
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

Keys bound as of Sprint 18: `a`=enhance, `A`=remove-enhance, `m`=smooth, `M`=remove-smooth, `q`=denoise, `h`=sharpen, `H`=remove-sharpen, `u`=upscale-2x, `U`=remove-upscale, `s`=scale-to-native, `f`=scale-to-fill, `r`=rotate-CW, `R`=rotate-CCW, `n`=show-filename, `x`=favourite, `v`=favourites-only, `t`=thumbnails, `i`=image-info, `z`=smart-zoom, `/`=keyboard-shortcuts, `d`=debug-window, `j`=random-jump, `b`=before/after-preview, `e`=adjustments-hud.

Free slots: `c`, `g`, `k`, `l`, `o`, `p`, `w`, `y` (and uppercase variants of unused keys).

SwiftLint `cyclomatic_complexity` error threshold is ~50. Run `xcodebuild | grep cyclomatic` after adding keys.

**Why:** `j` was missing from the registry in Sprint 17's memory — caused a key conflict when planning Sprint 18 (#167 initially proposed `j`). Always read the actual code, not just the registry.

---

## SlideshowView.swift size limits

As of Sprint 18 the file is ~3177 lines. `.swiftlint.yml` thresholds raised to error at 3500 (file) / 3000 (type body). The next substantial editing feature should extract HUD functions to `SlideshowView+Edits.swift`, changing `@State private var` to `@State var` (internal) on anything the extension needs.
