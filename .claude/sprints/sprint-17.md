# Sprint 17 — ai-ml (Apple frameworks)

Started: 2026-06-29
Status: complete

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 161 | Image sharpening via CISharpenLuminance | SlideshowView.swift, SlideyApp.swift | opus | — |
| 166 | Denoise HUD: real-time noise reduction slider | SlideshowView.swift, SlideyApp.swift | opus | #161 |
| 162 | Stylistic photo effects: B&W, Sepia, Fade (CIPhotoEffect*) | SlideshowView.swift, SlideyApp.swift | opus | #166 |
| 160 | Smart zoom: saliency-based auto-crop display mode | SlideshowView.swift, SlideyApp.swift | opus | #162 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| 159 | Background removal (VNGenerateForegroundInstanceMaskRequest) | Slots full; defer to sprint 18 |
| 163 | Face restoration (GFPGAN/CodeFormer) | Requires sourcing external Core ML model; S-Lab license unclear |
| 164 | JPEG artifact removal (SwinIR) | Requires sourcing community Core ML export; not bundled |
| 165 | B&W photo colorization (DDColor) | Requires sourcing external Core ML model (50–200 MB) |

## Notes

- All 4 issues use built-in Apple frameworks only (Core Image, Vision) — no external ML models needed.
- All touch SlideshowView.swift (hot file) → fully serialized via blockedBy chain.
- Group B issues (#163, #164, #165) need model sourcing + license review before they can be scheduled.

## Results

Released: v1.16 — 2026-06-29

### Shipped

- #161 Image sharpening (CISharpenLuminance) — key: h / Edit > Sharpen Image
- #166 Denoise HUD — real-time CINoiseReduction slider; key: q / Edit > Denoise…
- #162 Stylistic photo effects (Mono, Noir, Fade, Chrome, Process, Tonal) — Edit > Photo Effect submenu
- #160 Smart zoom — VNGenerateAttentionBasedSaliencyImageRequest zooms to subject; key: z / View > Smart Zoom

### Stats

- PRs merged: 4 (#176, #177, #178, #179)
- CI wall time per PR: ~2 min
- All CI checks green on main
