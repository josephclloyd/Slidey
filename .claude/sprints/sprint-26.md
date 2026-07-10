# Sprint 26 — 2026-07-10

Started: 2026-07-10T00:00
Status: planned

## Theme: Smarter denoising (Joe-scoped: #240, #241 only)

Joe explicitly scoped this sprint to two specific issues (`/sprint plan 240 241`) rather
than a full backlog survey — both were freshly filed this same day, following up on a
question about improving grainy-image handling beyond the existing classical Denoise HUD
(#166) and JPEG-artifact-focused SwinIR tool (#164). No open `meta`-labelled issues this
cycle.

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 241 | Auto-detect noise and suggest denoising | SlideshowView.swift, ImageLoader.swift | opus | — |
| 240 | Smarter ML-based denoiser (alternative to classical CINoiseReduction) | SlideshowView.swift, SlideshowView+AIEdits.swift | opus | #241 |

Both touch `SlideshowView.swift` and are serialized per the hot-file rule. Only 2 issues
this cycle (Joe's explicit scope), well under the usual 5-issue sprint size — no batching
decision needed.

## Notes per issue

**#241 (Auto-detect/suggest, first):** Purely additive and lower-risk — a background noise
estimate on thumbnail-resolution images plus a dismissible toast, reusing the existing
`showSavedToast` pattern and the "never decode the full bitmap for a cheap check" principle
CLAUDE.md already documents for thumbnails. No new persisted state beyond a session-only
per-URL dismissed-suggestions set. Must not fire during slideshow auto-advance or when an
image already has a denoise level applied. Placed first since it's self-contained and
doesn't depend on #240's model work — the suggestion just points at the *existing* classical
Denoise HUD (`q`), not the new ML tool specifically.

**#240 (ML denoiser, second):** Higher risk and more open-ended — the issue's own notes
flag genuine uncertainty about whether the already-bundled `SwinIR_color_jpeg40.mlpackage`
(currently used only for JPEG artifact removal, #164) generalizes to general sensor noise,
or whether this needs its own dedicated denoising model. Impl session should verify against
a real noisy (not just compressed) test image *before* committing to the reuse-SwinIR path,
and fall back to scoping a new bundled model if it doesn't generalize — flag this explicitly
to the impl session at spawn time given the sprint's established pattern of surfacing known
risks directly rather than relying on the issue text alone. Also needs a design decision
(replace the classical Denoise HUD outright vs. ship as a separate "AI Denoise" toggle
alongside it, per the issue's own notes) — lean toward the separate-toggle option unless the
impl session finds a strong reason otherwise, since it's lower-risk and matches how
Sharpen/Artifact-Removal already coexist as separate single-purpose tools.

## Excluded (with reasons)

N/A — this sprint is explicitly scoped to #240 and #241 only, not a backlog survey. The
rest of the open backlog (#219 object removal, #135 share sheet) is unchanged from Sprint
25's assessment and wasn't reconsidered this cycle.

## Notes

(anything surprising from planning goes here once we start)
