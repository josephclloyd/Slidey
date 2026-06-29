# Sprint 18 — photo-editing (Core Image)

Started: 2026-06-29
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 173 | Before/After toggle: hold key to preview original | SlideshowView.swift | opus | — |
| 170 | Flip horizontal and vertical | SlideshowView.swift, SlideyApp.swift | opus | #173 |
| 171 | Vignette effect with intensity slider | SlideshowView.swift, SlideyApp.swift | opus | #170 |
| 167 | Adjustments HUD: exposure, highlights/shadows, vibrance, warmth | SlideshowView.swift, SlideyApp.swift | opus | #171 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| 168 | Crop: drag to select and crop region | Drag gesture over existing pan/zoom is high-risk; complex coordinate math; defer |
| 169 | Straighten: arbitrary rotation angle with slider | Key `r` proposed in issue is already taken (rotate CW); needs redesign |
| 172 | Red-eye removal | Needs Vision face detection + manual click fallback; more scope than fits here |
| 174 | Copy/paste adjustments | Blocked — depends on #167 being shipped first |
| 159 | Background removal | Carried from sprint 17; no key binding decided |
| 163–165 | Face restoration, artifact removal, colorization | Require sourcing external Core ML models; licenses unresolved |

## Notes

- All 4 issues use built-in Core Image only — no external ML models.
- All touch SlideshowView.swift (hot file) → fully serialized via blockedBy chain.
- **Key binding conflict in #167:** issue body proposes `a` but that's taken by Enhance. Implementor should use `j` (free) or a menu-only trigger.
- **Key binding conflict in #169:** issue proposes `r` but taken by Rotate CW — reason for exclusion.
- #173 is the lightest (no filter chain, pure display bypass) — good first issue to validate the sprint pipeline.
- After #167 lands, #174 (copy/paste adjustments) becomes the natural sprint 19 opener.
