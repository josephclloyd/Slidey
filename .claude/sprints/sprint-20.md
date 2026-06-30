# Sprint 20 — 2026-06-30

Started: 2026-06-30T14:00
Status: planned

## Theme: AI/ML (CoreML models)

Sprint 17 shipped the Apple-framework AI features (smart zoom, photo effects, denoise, face
detection). Sprint 19 shipped CodeFormer (face restoration), red-eye, and background removal.
Sprint 20 completes the ai-ml backlog with two heavier model-based features: JPEG artifact
removal (SwinIR) and B&W photo colorization (DDColor).

## Pre-sprint model conversion (REQUIRED before running)

Both issues require a CoreML model to be converted and committed to the repo via LFS **before**
spawning impl sessions. Pattern from sprint 19 (CodeFormer):

```
1. Find or export model as CoreML .mlpackage
2. git lfs track "**/*.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
3. git add .gitattributes && git commit (on the feature branch)
4. Use MLModel(contentsOf:) + MLDictionaryFeatureProvider — NOT auto-generated bindings
```

### #164 — SwinIR (JPEG artifact removal)

Model: SwinIR-S (small variant) for JPEG artifact removal  
- Repo: https://github.com/JingyunLiang/SwinIR (Apache 2.0)  
- CoreML conversion: coremltools from PyTorch `.pth` checkpoint  
- Target checkpoint: `model_zoo/swinir_classical_sr_x2.pth` or the JPEG deblocking variant  
  (`experiment/swinir_s_x4_classical/models/` — look for `swinir_CAR_s126w7_jpeg10.pth`)  
- Input shape: `(1, C, H, W)` — patch or full image; confirm at conversion time  
- Expected model size: 10–30 MB (S variant)  
- If a community CoreML export exists on Hugging Face (search "SwinIR mlpackage"), prefer that  

### #165 — DDColor (B&W colorization)

Model: DDColor-compact  
- Repo: https://github.com/piddnad/DDColor (Apache 2.0)  
- Hugging Face: search "DDColor coreml" or "DDColor mlmodel" — community exports exist  
- If no direct CoreML export: convert with coremltools from the PyTorch checkpoint  
- Input: RGB image (model handles grayscale detection internally) at 512×512  
- Output: colorized RGB 512×512 or AB channels in LAB space (check model card)  
- Expected model size: 50–100 MB (compact variant)  
- LFS required — file exceeds GitHub's 100 MB limit for the full variant; use compact  

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 164 | JPEG artifact removal via SwinIR Core ML | SlideshowView.swift, SlideyApp.swift, Notifications.swift | opus | — |
| 165 | B&W photo colorization via DDColor Core ML | SlideshowView.swift, SlideyApp.swift, Notifications.swift | opus | #164 |

Both touch `SlideshowView.swift` — #165 blocked by #164 to avoid merge conflicts.

## Key bindings

Free slots (from CLAUDE.md registry): `l`, `o`, `w`, `y` (and uppercase variants).

Proposed assignments:
- `l` / `L` — Remove Artifacts / Remove Artifact Correction (artifact removal is a "light" touch)
- `o` / `O` — Colorize / Remove Colorization (o for "old photos")

Confirm with Joe before assigning; alternatives welcome.

## Implementation notes — #164 (SwinIR artifact removal)

**Pipeline position:** base-image edit (like upscale/CodeFormer). Store result in
`artifactRemovedImages: [URL: NSImage]`. Call `setDisplay(base:for:)`.

**Compositing priority** (proposed): insert between `faceRestored` and `upscaled`:
`bgRemoved > faceRestored > artifactRemoved > upscaled > sharpened > smoothed > enhanced > original`

Rationale: artifact removal should precede upscaling (SwinIR cleans the source; RealESRGAN
upscales the cleaned result), but is a less fundamental edit than face restoration.

**Model input/output:**
- Input: full image or 256/512 patch (depends on exported model — check at conversion time)
- Output: same dimensions, cleaned image
- Normalise to `[0, 1]` (not `[-1, 1]` like CodeFormer)
- Channel order: RGB (not BGR like some PyTorch models — verify during conversion)

**HUD:** Not needed — one-shot operation, same as CodeFormer.

**Progress indicator:** Reuse the `isProcessing` flag + existing progress overlay pattern.

**Alert for no change:** No face-gate needed; just apply to whatever image is current.

## Implementation notes — #165 (DDColor colorization)

**Pipeline position:** base-image edit. Store result in `colorizedImages: [URL: NSImage]`.
Call `setDisplay(base:for:)`.

**Compositing priority:** outermost base (applied before any other edit):
`colorized > bgRemoved > faceRestored > artifactRemoved > upscaled > ...`

Rationale: colorization replaces the entire tonal structure; other edits should apply
on top of the colorized result.

**Grayscale detection:** Use `CGImage.bitsPerComponent` + channel comparison. If the image
is already color, show a confirmation alert ("This appears to be a color image. Colorize anyway?")
rather than blocking silently.

**Model I/O (DDColor):**
- Input: RGB 512×512 float32 (model applies its own normalization internally)
- Output: RGB 512×512 colorized
- Resize source image to 512×512 for inference, then scale result back to original dimensions

**Key:** `o` = colorize, `O` = remove colorization.

## Excluded

No issues excluded. Sprint 20 is intentionally lean (2 issues) because both require:
1. Pre-sprint model work (find, convert, commit via LFS)
2. Heavy background inference (larger models than sprint 19's CodeFormer)

If pre-sprint model work fails for one (no suitable CoreML export found), that issue
moves to the "needs-attention" pile and the sprint runs with 1 issue.

## Notes

- SlideshowView.swift is at 3484 lines after fixing #192. SwiftLint error threshold is 3500.
  Both issues add ~50-100 lines each → WILL exceed threshold. Plan: extract face/edit 
  functions to `SlideshowView+AIEdits.swift` extension as part of whichever issue hits 3500 first.
- The `convert_codeformer.py` pattern from sprint 19 should be replicated: commit a
  `convert_swinir.py` / `convert_ddcolor.py` script alongside the model for reproducibility.
- CI: both models need `lfs: true` in checkout steps (already in `build.yml` from sprint 19).
