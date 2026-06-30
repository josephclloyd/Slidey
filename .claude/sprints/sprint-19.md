# Sprint 19 — 2026-06-29

Started: 2026-06-29T16:30
Status: planned

## Pre-sprint

CodeFormer converted to Core ML before the sprint started:
- `slidey/Resources/CodeFormer.mlpackage` (180 MB, float16)
- `slidey/Resources/convert_codeformer.py` — conversion script for reproducibility
- API: `CodeFormerInput(face: MLShapedArray<Float16>)` → `CodeFormerOutput.restored_face`
- Input/output shape `(1,3,512,512)`, values in `[-1,1]`
- Async prediction available (macOS 14+, well within our 15.0 floor)
- Build: model compiles cleanly, Xcode generates Swift bindings automatically

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 186 | Add keyboard shortcuts for Flip H/V | SlideshowView.swift | opus | — |
| 163 | Face restoration via Core ML (CodeFormer) | SlideshowView.swift | opus | #186 |
| 172 | Red-eye removal | SlideshowView.swift | opus | #163 |
| 159 | Background removal via Vision framework | SlideshowView.swift | opus | #163 |

All four touch `SlideshowView.swift` — serialize them via `addBlockedBy` edges as shown.

## Implementation notes — #163 (CodeFormer)

**Pipeline position:** Face restoration is a base-image edit (like upscale), not a compositing
layer. Store result via `setDisplay(base: result, for: url)`. Do NOT add it to `updateDisplayImage`.

**Integration sketch:**
```swift
// Key: 'p' (free slot from registry)
// Flow: detect face crop → run CoreML → paste back → setDisplay(base:for:)
let config = MLModelConfiguration()
config.computeUnits = .all
let model = try await CodeFormer.load(configuration: config)
let input = CodeFormerInput(face: faceAsMLShapedArray)
let output = try await model.prediction(input: input)
// output.restored_face is Float16 (1,3,512,512) in [-1,1]
```

**Face detection:** Use `VNDetectFaceRectanglesRequest` to find face bounds, crop to 512×512,
run CodeFormer, paste result back, then call `setDisplay`. If no face detected, show alert.

**Key binding:** `p` (free) for "restore faces". HUD not needed — it's a one-shot operation
like upscale. Add progress indicator same as upscale (progress overlay).

**SlideshowView.swift size:** Currently ~3177 lines. CodeFormer feature will add ~150-200 lines.
SwiftLint error threshold is 3500. Should be fine, but check `| grep file_length` after first
build. If over, extract face-restoration code to `SlideshowView+FaceRestore.swift`.

## Implementation notes — #186 (Flip shortcuts)

Issue asks for `c`/`C` key bindings:
- `c` = Flip Horizontal
- `C` = Flip Vertical (or vice versa — implement whichever is more intuitive, note in PR)

Confirm `c` is free: `grep "case \"c\"" slidey/SlideshowView.swift` should return nothing.

## Implementation notes — #172 (Red-eye removal)

Red-eye detection: `VNDetectFaceRectanglesRequest` to find eyes region, then `CIRedEyeCorrection`
filter. Applies to the base image (like CodeFormer), route through `setDisplay`. Key: one of
`g`/`k`/`l`/`o` (all free).

## Implementation notes — #159 (Background removal)

Uses `VNGenerateForegroundInstanceMaskRequest` (macOS 14+). Returns a mask; apply with
`CIBlendWithMask` to composite subject over transparency or white. Route through `setDisplay`.
Key: one of the remaining free slots.

## Excluded

- No issues excluded this sprint. #174 (slideshow timer) deferred — #186/#163/#172/#159 form
  a coherent "image enhancement" batch and four issues already fills the sprint.

## Notes

- All four issues are SlideshowView-heavy; the blocking chain (186→163→172,159) keeps them
  serialized so there are no merge conflicts.
- 159 (Background removal) depends on Vision framework features available macOS 14+ — no
  `@available` guards needed (deployment target is 15.0).
- CodeFormer model is 180 MB — consider lazy loading (load on first use, cache instance).
  Compare with RealESRGAN pattern in SlideshowView.swift.
