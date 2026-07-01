# Sprint 20 — 2026-06-30

Started: 2026-06-30T14:00
Status: models-ready

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

**Converted 2026-06-30 — ready to commit.**

Model: SwinIR-M `006_colorCAR_DFWB_s126w7_SwinIR-M_jpeg40` (Apache 2.0)
- Repo: https://github.com/JingyunLiang/SwinIR
- Weights: HuggingFace piddnad/DDColor-models → `ddcolor_paper_tiny.pth` (no; see actual note)
  Actual: GitHub releases page of JingyunLiang/SwinIR, JPEG CAR model
- File: `slidey/Resources/SwinIR_color_jpeg40.mlpackage`
- Conversion script: `slidey/Resources/convert_swinir.py`
- 11,492,067 params; traced at 126×126 (native training size — prevents shift-mask error)
- Input: (1, 3, 126, 126) float32 RGB [0,1]
- Output: (1, 3, 126, 126) float32 RGB artifact-removed [0,1]
- Compiled weight.bin: ~25 MB (tracked via LFS)
- Swift: tile source into overlapping 126×126 patches, run per-tile, blend/reassemble
- Conversion notes:
  - Cannot trace at 256×256 (OOM during trace) or 128×128 (coremltools shift-mask bug)
  - 126×126 is the only safe trace size; other sizes trigger `slice_by_index` error
  - `ct.convert()` triggers ANE compilation internally; expect 30–90 min per model

### #165 — DDColor (B&W colorization)

**Converted 2026-06-30 — ready to commit.**

Model: DDColor paper-tiny (Apache 2.0)
- Repo: https://github.com/piddnad/DDColor
- Weights: HuggingFace piddnad/DDColor-models → `ddcolor_paper_tiny.pth` (210 MB)
- File: `slidey/Resources/DDColor_paper_tiny.mlpackage`
- Conversion script: `slidey/Resources/convert_ddcolor.py`
- 55,006,640 params; traced at 512×512
- Input: (1, 3, 512, 512) float32 — grayscale-encoded RGB [0,1]
  (L channel from Lab, replicated to R=G=B, /100 for [0,1])
  Model applies ImageNet normalisation internally.
- Output: (1, 2, 512, 512) float32 — AB Lab channels (raw)
- Compiled weight.bin: 115 MB (tracked via LFS); LFS required
- Swift: extract L from Lab, replicate → inference → upsample AB → merge with orig L → RGB
- No pre-existing CoreML export on HuggingFace (searched 2026-06-30)  

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

## Results

Released: v1.19 — 2026-07-01

### Shipped
- #164 JPEG artifact removal via SwinIR Core ML (`l` / `⇧L`) — tiled 126×126 inference with
  linear-ramp overlap blending. PR #195, one repair round.
- #165 B&W photo colorization via DDColor Core ML (`o` / `⇧O`) — Lab L/AB pipeline at 512×512,
  with grayscale detection + confirmation alert for already-color images. PR #196, one repair round.

### Deviations from plan
- The extraction to `SlideshowView+AIEdits.swift` (anticipated in the pre-sprint notes above)
  happened as a **repair fix** on #164 rather than as part of the initial implementation — the
  impl session instead bumped SwiftLint's `file_length`/`type_body_length` thresholds to paper
  over the overage. Caught in review, reverted, and extracted properly. `SlideshowView.swift`
  ended the sprint at 3304 lines (down from 3702 mid-sprint), well under the original 3500 guardrail.
- #165's impl session hit the usage quota mid-task with substantial uncommitted, buildable work
  (core DDColor pipeline, menu/key wiring, tests) and no commits yet. Resumed the same session
  after the quota reset rather than discarding — it finished the missing grayscale-detection
  alert, updated CLAUDE.md, and opened the PR.
- #165 review round 1 caught a real concurrency bug: `restoreFacesOnCurrentImage` and
  `removeArtifactsOnCurrentImage` didn't guard against `isColorizing`, allowing a race if
  colorization ran concurrently with those operations. Fixed in repair.

### Needs attention
None — both issues merged clean.

### Stats
- PRs merged: 3 (#194 pre-sprint models, #195, #196)
- Repair rounds: 1 for each of #164 and #165 (both caught real issues, not false positives)
- Total session cost: ~$10.91 across impl/review/repair sessions
- CI wall time per PR: ~2.5–4 min
