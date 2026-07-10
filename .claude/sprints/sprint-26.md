# Sprint 26 — 2026-07-10

Started: 2026-07-10T00:00
Status: shipped

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

## Results

Released: v1.25 — 2026-07-10

### Shipped
- #241 Auto-detect noise and suggest denoising — PR #243, 0 repair rounds, clean on first
  review (one non-blocking nit noted: an unstored `Task` whose cancellation check is dead
  code, harmless given the URL guard already protects it).
- #240 Smarter ML-based denoiser (ships as a separate "AI Denoise" tool, `Shift+Q`,
  alongside the existing classical Denoise HUD) — PR #244, 1 repair round (two findings:
  the PR claimed a shared `runSwinIRInference()` helper was extracted from artifact
  removal, but `removeArtifactsOnCurrentImage()` still had its own ~160-line inline copy
  of the same pipeline — the extraction was only applied to the new AI Denoise path, not
  backported; and the new `.aiDenoise` edit step's `Codable`/`caseTag`/`displayName`
  round-trip had no tests, contrary to CLAUDE.md's testability requirement for pure
  model/state changes). The impl session's own scoping note is worth keeping: the bundled
  SwinIR model was trained for JPEG artifact removal, not general sensor noise — it's
  documented honestly in the PR as "AI Denoise" rather than overclaiming superiority over
  the classical filter in all cases, with a dedicated NAFNet/Restormer-class model flagged
  as the real follow-up if true sensor-noise superiority is wanted later.

### Deviations from plan
- **A large mid-sprint discussion about Anthropic account quota/billing**, prompted by Joe
  noticing `mcx status`'s `Extra` usage line jump from `$0/$4600` to `$336/$4600` between
  checks. Investigated: `hasExtraUsageEnabled: true` in the local Claude Code account
  config confirmed extra usage was already enabled account-wide (not a toggle I needed to
  flip); the `$X/$4600` figure appears to be a locally-tracked spend/budget-alert metric,
  not the authoritative Anthropic-side balance. Net effect: quota-hit retries were worth
  attempting more readily than assumed — a resume attempt after the reported reset time
  succeeded even while `mcx status` still showed the 5h window at 100%, confirming the
  displayed reset timestamp (and even 100%-used readings) can lag the actual server-side
  state by a meaningful margin, consistent with prior sprints' notes on this lag but with
  a clearer resolution this time: **just try the resume — it costs nothing to attempt, and
  it succeeded well before the locally-displayed reset time.**
- **Quota hit once mid-session** (#240's impl, 56 turns before the hit) — resumed via a
  simple "try continuing now" nudge rather than waiting out the full displayed window,
  per the finding above. No lost work.

### Needs attention
None — both issues merged clean.

### Stats
- PRs merged: 2 (#243, #244)
- Repair rounds: #241 — 0; #240 — 1 (real findings: incomplete refactor claim, missing
  tests)
- Quota-hit recoveries: 1 (#240's impl — resumed successfully before the displayed reset
  time)
- Follow-up issues filed: none this sprint
- Total orchestration cost: ~$13 across 6 spawned sessions (3 opus impl/repair, 3 sonnet
  review)
