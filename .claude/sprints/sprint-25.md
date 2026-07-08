# Sprint 25 — 2026-07-08

Started: 2026-07-08T00:00
Status: planned

## Theme: Backlog refill — precision editing tools + un-staled quick wins

Sprint 24 shipped clean at 5 issues with 1 real repair round, so Sprint 25 stays at 5. The
backlog was thin at planning time (only 4 open issues, 3 previously stale/deferred) — this
sprint's plan includes un-staling #138, and 3 freshly drafted issues (#229, #230, #231) to
refill the backlog, per Sprint 24's own anticipation of this moment. No open `meta`-labelled
issues this cycle.

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 231 | Color histogram in Adjustments/Curves HUD | SlideshowView.swift, SlideshowView+Curves.swift | opus | — |
| 174 | Copy/paste adjustments between images | SlideshowView.swift, SlideshowView+BatchApply.swift, SlideyApp.swift | opus | #231 |
| 138 | Export current image with edits applied (Save a copy) | SlideshowView.swift, SlideyApp.swift | opus | #174 |
| 230 | Perspective/keystone correction | SlideshowView.swift, SlideyApp.swift, CLAUDE.md | opus | #138 |
| 229 | Local/selective adjustments: brush-based dodge/burn masking | SlideshowView.swift, SlideyApp.swift, CLAUDE.md | opus | #230 |

All five touch `SlideshowView.swift`'s `overlayViews`/`coreView` sections and are serialized
into one chain per the hot-file rule. Ordered lowest-risk/most-additive first, most-invasive
last.

## Notes per issue

**#231 (Histogram):** Purely additive — a passive readout piggybacking on the Adjustments
HUD's (#167) and Curves HUD's (#220) existing debounced preview pipeline via `CIAreaHistogram`.
No new key binding, no new per-image state. Placed first as the lowest-risk issue.

**#174 (Copy/paste adjustments, now un-stale):** Previously flagged stale across Sprints
21-23 because its `ImageAdjustments` struct predated the current `EditStack`/crop/vignette/
curves/straighten architecture. Un-staled this planning cycle: #221 (Sprint 24, just shipped)
already built the exact "copy an edit stack to target URLs" mechanism in
`SlideshowView+BatchApply.swift` — this issue is now a thin single-target wrapper around
that existing, already-tested code rather than a fresh design. Impl session should reuse
`SlideshowView+BatchApply.swift`'s copy logic with a target set of exactly one URL (the
current image) instead of writing new copy logic from scratch.

**#138 (Export with edits, rewritten):** Rewritten this planning cycle against the current
pipeline — the original spec (2026-06 era) predated `EditStack`, crop, straighten, curves,
and vignette. New body (see issue) enumerates the exact current `updateDisplayImage()`
compositing order: AI edit stack → flip → photo effect → adjustments → curves → vignette →
straighten → crop, plus the 90°-step `rotationAngle` which is a **view-level** transform not
otherwise baked into pixels and must be applied separately for export. Impl session should
extract `updateDisplayImage()`'s compositing sequence into a shared helper if one doesn't
already exist, so export and live display can never drift out of sync.

**#230 (Perspective correction):** New Vision-based tool (`VNDetectRectanglesRequest` +
`CIPerspectiveCorrection`) with a four-corner drag-handle overlay, complementing Straighten
(#169, Sprint 24) which only handles camera-tilt rotation, not perspective distortion. Placed
after the two simpler un-staled issues so it gets a full, unrushed pass — new interaction
mode (corner dragging) plus a Vision detection call, more novel than #174/#138's reuse of
existing patterns.

**#229 (Local/selective adjustments):** The most invasive and novel issue this sprint — a
new brush-painting interaction mode, mask-based compositing via `CIBlendWithMask`, and
multiple stored mask layers per image (a new shape of per-image state, unlike every other
issue this sprint which reuses existing dict-of-scalar-per-URL patterns). Placed last so it
gets the freshest context and doesn't block the four more straightforward issues behind it
in the queue if it runs long.

## Excluded (with reasons)

- **#219 Object removal (inpainting)** — still blocked on a Core ML model-acquisition
  prerequisite (no inpainting model in the repo yet), same as Sprint 24's assessment. Not
  re-attempted this sprint; would need its own "obtain and commit model files" issue filed
  first, mirroring the #150 → #151 upscaling precedent.
- **#135 Share current image via Share sheet** — still deferred per Joe's explicit request
  (carried forward from Sprint 22/23/24 with no change in status this cycle).

## Notes

Backlog was refilled this cycle specifically because it ran thin — 3 of Sprint 25's 5 issues
(#229, #230, #231) were freshly drafted during this planning session rather than pre-existing
backlog items. All three deliberately scoped as content-agnostic, non-destructive editing
tools (histogram, perspective correction, local brush adjustments) rather than anything
generative or identity-specific.
