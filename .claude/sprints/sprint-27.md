# Sprint 27 — 2026-07-14

Started: 2026-07-14T00:00
Status: shipped

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 235 | Batch-apply missing straighten and denoise coverage | SlideshowView+BatchApply.swift, SlideshowView+CopyPasteAdjustments.swift | opus | — |
| 135 | Share current image via macOS Share sheet | SlideyApp.swift, SlideshowView.swift (thin receiver), Notifications.swift | opus | — |
| 219 | Object removal (inpainting) | SlideshowView.swift, EditStack.swift, Notifications.swift, new SlideshowView+ObjectRemoval.swift, new bundled Core ML model | opus | #135 |

No meta-labelled issues open this cycle. All 3 open issues from `josephclloyd` are included —
thin backlog (only 3 candidates total), so no batching decision needed beyond the one
required serialization.

## Notes per issue

**#235 (batch-apply fix, no dependency):** Confirmed real during planning by reading
`SlideshowView+BatchApply.swift` directly — the `hasEdits` guard (lines 21-29) omits
`denoiseURLLevels` even though denoise is applied unconditionally later in the function
(lines 127-131), and `straightenAngles` isn't read/written anywhere in the file at all.
`SlideshowView+CopyPasteAdjustments.swift` already has both right (verified: reads
`straightenAngles[sourceKey]` at line 18, round-trips it at 148-151). Issue's own ask to
extract a single shared "collect this image's copyable edit state" helper is worth doing —
don't just patch the two lists independently again. Doesn't touch `SlideshowView.swift`, so
no conflict with #135 or #219; can run any time.

**#135 (share sheet, no dependency, placed first among the SlideshowView.swift-touching
pair):** Small and low-risk — `NSSharingServicePicker` anchored to the window, standard
menu-command → notification → receiver pattern already used throughout. Placed ahead of
#219 specifically so the larger issue doesn't block a quick one, and so #219 only has to
rebase against one small, fast-merging diff rather than sitting blocked on itself.

**#219 (object removal, blocked by #135):** Highest-risk issue this sprint — same risk
class as #240 (sprint 26)'s model-conversion work. No existing Vision/Core ML inpainting
model is bundled; likely path is converting LaMa or MI-GAN to `.mlpackage`, following
CLAUDE.md's established conversion gotchas: set `compute_precision=ct.precision.FLOAT32`
explicitly (don't rely on the FLOAT16 default), expect custom ops (e.g. any GAN-specific
normalization) may need monkey-patched substitution rather than being unconvertible, and
verify against real photo content (not just synthetic test input) before committing to a
model choice — NAFNet's real-photo failure in #253 is the cautionary example. Flag this
explicitly to the impl session at spawn time. Also flag `SlideshowView.swift`'s current
size (3,486 lines, well past the 2,000-line introspection threshold, with a known Xcode
16.3 type-checker timeout gotcha already documented in CLAUDE.md) — push new state/logic
into a new `SlideshowView+ObjectRemoval.swift` extension rather than growing `body`,
`coreView`, or the `@ViewBuilder` content vars directly. Selection UX can reuse the crop
tool's drag-rect pattern as a starting point per the issue's own notes. If the impl session
finds no suitable pretrained inpainting model converts cleanly within reasonable effort,
it should say so and scope a fallback rather than shipping something broken — same posture
as #240's "verify before committing to the reuse path" note from last sprint.

## Excluded

None — all 3 open `josephclloyd` issues included.

## Notes

- `SlideshowView.swift` line count has grown to 3,486 lines (was 1,558 at sprint 1, ~1,900
  as of the CLAUDE.md hot-file description, which is now stale). This crossed the
  introspection skill's 2,000-line concern threshold a while ago. Sprint 27 ends in 7, so
  the retro-phase introspection audit is due this cycle regardless — its findings should
  include a recommendation on whether to open a dedicated extraction sprint.
- No open introspection-findings issue was found from sprint 17 or sprint 7 (searched all
  states, no match) — either those audits weren't run, or didn't produce a filed issue.
  Worth confirming during retro.
- `mcx` was not on `$PATH` in this shell (only found at `/Users/joe/.mcp-cli/bin/mcx`,
  outside `$PATH`) — noting here in case `/sprint run` needs it; may just be this session's
  environment.

## Results

Released: v1.26 — 2026-07-15

### Shipped
- #235 Batch-apply missing straighten and denoise coverage — PR #257, 0 repair rounds.
  Impl session went beyond the stated scope in a good way: also fixed perspective-corners
  copying and extracted a single shared `collectCopyableEdits(from:)`/
  `applyCopiedEdits(_:to:)` helper used by both batch-apply and copy/paste, plus fixed
  `hasEdits` to check the filtered `batchableStack` (an image with only non-batchable AI
  edits no longer falsely passed the guard). Tests added for the newly extracted
  computed properties.
- #135 Share current image via macOS Share sheet — PR #256, 1 repair round (missing test
  for the new `.shareImage` notification in `FileMenuNotificationTests`, same pattern as
  sibling notifications — fixed, then round-2 review clean).
- #219 Object removal (inpainting) via bundled LaMa Core ML model — PR #258, 1 repair
  round. Highest-risk issue this sprint, and it showed: the impl session hit a mid-session
  quota cutoff after 120 turns, discovered LaMa's FFT-based convolutions (`fft_rfft2`)
  don't convert with coremltools and had to work around it (see
  `slidey/Resources/convert_lama.py`), and left the branch in a non-building state when
  quota ran out. Recovered orchestrator-side rather than discarded (real progress, not a
  zero-commit failure): missing `project.pbxproj` registration for the new source file, a
  `.rotationEffect(.degrees(_:))` type error, a SwiftUI type-checker timeout (the two new
  `.onReceive` handlers pushed `body`'s 105-modifier chain over budget — split into 5
  helper functions), a resulting SwiftLint `file_length`/`type_body_length` **error**
  threshold breach (extracted ~180 lines into a new `SlideshowView+NotificationHandlers.swift`,
  widening ~30 previously-`private` `SlideshowView` members to internal so the split file
  could call them), and an 814MB stray Python venv from the model-conversion script that
  was tripping SwiftLint (removed, added `.venv/` to `.gitignore`). Round-2 review then
  found 3 real bugs (asymmetric HUD mutual-exclusion, missing slideshow-cancel handling,
  dead `inpaintProgress` state) — fixed in 1 repair round.

### Post-merge fix (not part of the original plan)
Joe live-tested Object Removal immediately after #219 merged and found the brush cursor
and inpaint mask preview didn't line up. Two distinct bugs, found and fixed same-day via
direct orchestrator work (not the spawn/review/repair pipeline — a live interactive bug
report, not a tracked issue):
- **Mask preview positioning** (PR #260, commit f5bb825): the preview used a hand-rolled
  `centerX`/`centerY` + pre-scaled `.frame()` + `.position()` + late `.rotationEffect()`
  instead of mirroring `ImageDisplayView`'s actual transform chain. Code-reasoned fix,
  *not* visually verified before Joe retested — first attempt at automated GUI
  verification (`cliclick`/`screencapture`) failed and leaked personal Mail/Finder windows
  via wrong window-bounds math (memory note filed: `feedback-no-automated-screenshots.md`).
- **Y-axis inversion in painting** (PR #260, commit 014e7fc): Joe's retest found the
  *real* remaining bug — dragging the brush down painted upward. `objectRemovalViewToImagePixel()`
  used a top-down normalized Y directly as a Quartz-native (bottom-up) `CGContext`
  coordinate with no flip. Fixed by flipping `py = (1 - norm.y) * maskHeight`. Confirmed
  working by Joe on retest.
- Filed #261 to check whether `LocalAdjustmentController` has the identical latent bug
  (same unflipped-CGContext pattern) — not fixed here since it wasn't reported broken and
  touches shared, shipped code.

### Also filed this sprint
- #259 — Add in-app documentation for AI/editing tools to the Help menu (Joe's request,
  mid-sprint; the growing list of similarly-named tools — Denoise/JPEG Cleanup/AI Grain
  Reduction, Face Restore/Red-Eye/Background Removal — has no in-app explanation of scope
  differences).
- #261 — Check Local Adjustments brush for the same Y-axis mask inversion as Object
  Removal (see above).

### Deviations from plan
- **Quota hit twice.** First: a genuine ~2h21m five-hour-window exhaustion during #135's
  round-2/3 review — waited it out (two intermediate resume attempts failed instantly,
  confirming the local `quota_status` reading, while sometimes stale-in-Slidey's-favor per
  prior sprints' notes, was accurate this time). Second: mid-#219-impl, resulting in the
  orchestrator-side recovery described above.
- **`review.ts`'s `review_round` state needed manual correction twice** — a quota-failed
  spawn attempt (0 tokens, immediate error, no actual review performed) still incremented
  the phase engine's internal round counter, which would have prematurely tripped the
  "exceeded max review rounds → needs-attention" path on the next real attempt. Reset via
  `phase_state_set` both times before retrying. Worth a phase-engine fix: don't count a
  round that produced zero tokens/no verdict.
- **`done.ts`'s internal `git pull` left the main checkout in detached-HEAD-at-FETCH_HEAD
  state once** (after #235 merged) — same failure mode documented in `run.md` from Sprint
  24. Recovered with a plain `git checkout main`, per the documented fix.
- **Automated GUI verification attempted and abandoned.** See post-merge fix section above
  and the new memory note — not a repeatable capability for this project going forward.
- Two follow-up commits (the memory note, and PR #260's two commits) were orchestrator work
  outside the normal impl/review/repair session pipeline — appropriate given they were
  either non-code (memory) or a live bug fix requiring direct back-and-forth with Joe
  rather than an autonomous session.

### Needs attention
None outstanding — #260 merged, all three planned issues merged, no open PRs.

### Stats
- PRs merged: 4 (#257, #256, #258, #260)
- Issues filed: 2 (#259, #261) — both open, backlog for a future sprint
- Repair rounds: #235 — 0; #135 — 1 (real); #219 — 1 (real, 3 findings)
- Quota-hit recoveries: 2 (one ~2h21m genuine wait, one mid-impl requiring branch recovery)
- Memory writes: 1 (`feedback-no-automated-screenshots.md`)
- Total orchestration cost: ~$14.68 across 12 spawned sessions (5 opus impl/repair, 7
  sonnet review), plus direct orchestrator work for the #219 quota recovery and both
  post-merge fixes (not session-spawned, so not reflected in the dollar figure above)
