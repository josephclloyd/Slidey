# Sprint 24 — 2026-07-06

Started: 2026-07-06T00:00
Status: planned

## Theme: Investigation follow-up + tonal/geometric editing expansion

Sprint 23 shipped clean at the scaled 5-issue size (all merged, 0-1 repair rounds), so
Sprint 24 stays at 5. No open `meta`-labelled issues this cycle.

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 216 | Flaky test: DirectoryMissingTests.testDirectoryRecoveryAfterReappearing | SlideyTests/ImageLoaderTests.swift, ImageLoader.swift | opus | — |
| 220 | Curves/levels color grading tool | SlideshowView.swift | opus | — |
| 221 | Batch-apply current edit stack to a directory or favourites selection | SlideshowView.swift, SlideyApp.swift | opus | #220 |
| 169 | Straighten: arbitrary rotation angle with slider | SlideshowView.swift, CLAUDE.md | opus | #221 |
| 136 | Trackpad swipe gestures to navigate images | SlideshowView.swift | opus | #169 |

Four of five (#220, #221, #169, #136) touch `SlideshowView.swift` and are serialized into
one chain per the hot-file rule. #216 doesn't touch that file, so it runs in parallel
alongside whichever chain issue is active (2 concurrent issues max).

## Notes per issue

**#216 (Flaky test):** Investigation gate required per `investigations.md` — the issue body
says "suspected cause", not a confirmed root cause, which is exactly the flaky-test archetype
the gate exists for. Spawn a nerd-snipe investigation session (`mcx claude spawn`, not the
Agent tool) to produce root cause + concrete fix plan as an issue comment *before* any impl
session starts. Hard gate: if the investigator can't produce both, the issue moves to
`needs-attention` instead of proceeding to impl.

**#220 (Curves):** Extends the existing Adjustments HUD (#167) rather than replacing it — a
new `CIToneCurve`-based control alongside exposure/highlights/shadows/vibrance/warmth in the
same `CIFilter` chain. Purely additive, placed first in the chain.

**#221 (Batch-apply):** Copies the current image's edit-stack dict entries to other URLs;
naturally sits after #220 so Curves values are already part of the stack it copies. Needs a
confirmation dialog before applying to N images and progress indication for large
directories (#108 precedent).

**#169 (Straighten):** The issue's own suggested key binding ("`r` opens straighten HUD,
`[`/`]` remain for 90° rotation") predates the current registry — CLAUDE.md now binds `r`/`R`
directly to 90° CW/CCW with no bracket keys in use anywhere. Impl session must pick a free
key from the current registry (check CLAUDE.md's key binding list before assigning) rather
than following the issue's stale suggestion. Sprint 23 flagged this as deserving focused
attention (comparable scope to the Sprint 21 crop feature) — placed after the two smaller
edit features so it gets an unrushed pass, before the higher-risk gesture work.

**#136 (Trackpad swipe):** Sprint 23 excluded this for interaction-design risk against two
existing gesture layers (`ZoomPanController`'s scroll-based pan, crop's `CropOverlayCatcher`).
Placed last — most invasive, needs gesture precedence reasoned through carefully (zoom > 1
must keep gating pan over swipe, per the issue's own acceptance criteria).

## Excluded (with reasons)

- **#219 Object removal (inpainting)** — newly filed; the natural implementation path
  (bundled Core ML inpainting model, e.g. LaMa/MI-GAN) has no model in the repo yet. AI
  upscaling needed its own model-acquisition issue first (#150, ahead of #151) — object
  removal likely needs the same "obtain and commit model files" prerequisite filed and
  closed before implementation is scheduled. Not attempted this sprint.
- **#174 Copy/paste adjustments between images** — still stale per Sprint 22/23 findings:
  the issue's `ImageAdjustments` struct predates Sprint 21's `EditStack`/crop/flip/vignette
  layers. Needs a fresh design pass against the current architecture before it's plannable.
- **#138 Export current image with edits applied** — same staleness as #174: written before
  the current `editStacks[url]` → flip → effect → adjustments → vignette → crop pipeline
  order existed. Needs redefinition before it's actionable.
- **#135 Share current image via Share sheet** — still deferred per Joe's explicit request
  (Sprint 22).

## Notes

(anything surprising from planning goes here once we start)
