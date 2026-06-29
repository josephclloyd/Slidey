---
name: project-sprint17-patterns
description: "Patterns established in Sprint 17 — image edit compositing, key binding registry, SwiftLint complexity limit"
metadata: 
  node_type: memory
  type: project
  originSessionId: d50fd14f-bc8a-4d35-981e-cd648fb3c1db
---

Sprint 17 shipped 4 AI/ML features (sharpen, denoise, photo effects, smart zoom) using Core Image and Vision. Key patterns that should carry forward:

**`setDisplay(base:for:)` compositing helper** — the canonical path for committing an edited NSImage in SlideshowView. It clears `effectImages[url]`, reapplies any active photo effect, and sets `currentDisplayImage`. All edit features (sharpen, smooth, denoise, upscale) must route through it. Do not assign `currentDisplayImage` directly.

**Why:** Without routing through this helper, photo effects applied before an edit are silently lost after the edit commits. Discovered during photo effects + denoise interaction design.

**How to apply:** Any new image-editing feature that produces a new NSImage result must call `setDisplay(base: result, for: url)` as its final step, not `currentDisplayImage = result`.

---

**`handleCharacterKeyPress` complexity limit** — keys already bound: `a`=enhance, `A`=remove-enhance, `m`=smooth, `M`=remove-smooth, `q`=denoise, `h`=sharpen, `H`=remove-sharpen, `u`=upscale-4x, `U`=remove-upscale, `s`=scale-to-native, `f`=scale-to-fill, `r`=rotate-CW, `R`=rotate-CCW, `n`=show-filename, `x`=favourite, `v`=favourites-only, `t`=thumbnails, `i`=image-info, `z`=smart-zoom, `/`=keyboard-shortcuts. SwiftLint `cyclomatic_complexity` error threshold is ~50. Check before adding new keys.

**Why:** Adding the `q` key in Sprint 17 pushed `handleKeyPress` over the threshold. Fix required extracting `handleCharacterKeyPress`. Key `n` was already taken by show-filename; denoise was moved to `q`.

**How to apply:** Before assigning a new key, check the registry above and run `xcodebuild | grep cyclomatic` after adding to confirm it stays green.
