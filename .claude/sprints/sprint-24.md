# Sprint 24 — 2026-07-06

Started: 2026-07-06T00:00
Status: shipped

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

## Results

Released: v1.23 — 2026-07-08

### Shipped
- #216 Fix flaky `DirectoryMissingTests.testDirectoryRecoveryAfterReappearing` — PR #224,
  0 repair rounds. Investigation gate ran first (session comment on #216) and produced an
  exact root cause (duplicate `directoryMissing = false` Combine emission from
  `ImageLoader.swift:81` racing the recovery timer) plus a 3-part fix plan that the impl
  session implemented unchanged.
- #220 Curves/levels color grading tool — PR #223, 0 repair rounds. Per-channel (All/R/G/B)
  `CIToneCurve` editing via a Catmull-Rom spline graph, extending the Adjustments HUD (#167)
  pattern. Hit the known `SlideshowView.swift` file-length SwiftLint gate from Sprint 20 and
  extracted to `SlideshowView+Curves.swift` as expected.
- #221 Batch-apply current edit stack to a directory or favourites selection — PR #225,
  1 repair round (real bug: `denoiseURLLevels` was missing the `else { removeValue }` clear
  branch that every other edit property has, so batch-applying an image with no denoise
  level left stale denoise values in `UserDefaults` on target images; fixed in commit
  `6e1d199`).
- #169 Straighten: arbitrary rotation angle with slider — PR #226, 0 repair rounds. Chose
  `y`/`Y` for straighten/remove-straighten after confirming the issue's own suggested keys
  (`r`, `[`/`]`) were stale against the current registry; CLAUDE.md updated. Composes with
  90° rotation cleanly since straighten operates on pixels while `rotationAngle` is a
  view-level `.rotationEffect`.
- #136 Trackpad swipe gestures to navigate images — PR #227, 0 repair rounds. The
  interaction-design risk flagged since Sprint 23 (conflict with `ZoomPanController`'s
  scroll-based pan and crop's `CropOverlayCatcher`) resolved cleanly: swipe is gated on
  `zoomScale == 1 && !cropController.isActive`, verified by review to correctly fall through
  to existing pan/crop behaviour in both cases. 9 new `SwipeTracker` unit tests.

Also included in this release but **not** part of Sprint 24's plan: #218 "Stop persisting
rotation, flip, vignette, adjustments, crop, and photo effect" (commit `d5e43b0`) merged
between Sprint 23's tag and this sprint's start.

### Deviations from plan

- **Quota hit mid-session five times** (#216's investigation, #220's impl, #169's impl,
  #136's impl, all opus) — each time recovered per `run.md`'s partial-progress procedure:
  confirmed the session was idle (not mid-commit), inspected what it had left behind, and
  sent a `mcx claude send` nudge describing exactly the remaining work once quota reset,
  rather than discarding and re-spawning fresh. All four resumed cleanly with no repeated
  work. #220's impl session was caught mid-way through the `SwiftLint file_length` extraction
  pattern (removed `curvesHUD` from `SlideshowView.swift` but hadn't yet populated the new
  `SlideshowView+Curves.swift`) — the nudge specified the exact missing piece so the resumed
  session didn't have to rediscover it.
- **#216's impl session's own `gh pr create` command failed** with a bash heredoc syntax
  error (`bad substitution: no closing ')'`) — the same class of shell-quoting bug hit
  independently earlier this session when filing GitHub issues. The session had already
  committed and pushed the fix; only PR creation failed. Recovered by creating PR #224
  manually with the body text visible in the session's own transcript.
  Not filed as a fresh issue — this is a shell-quoting hazard in ad-hoc heredoc use, not a
  code defect in the repo.
- **My own `git pull origin main`** (attempting to sync before starting #221) failed with a
  divergent-branches error and left the main checkout's HEAD detached at `FETCH_HEAD` instead
  of on the `main` branch. Local `main`'s ref already matched `origin/main` (the fetch had
  already fast-forwarded it), so recovery was a plain `git checkout main` — no reset or force
  needed. Should use `git fetch && git merge --ff-only` instead of bare `git pull` in this
  checkout going forward, to avoid the reconciliation prompt entirely.
- **Two review sessions (#220 round 1, #221 round 2's predecessor context) posted clearly
  approving comments but didn't emit the exact literal `VERDICT: clean` token** the review
  prompt asked for. Treated as clean based on comment content (unambiguous LGTM, no
  conditions) rather than re-spawning for a literal string match — worth tightening the
  review prompt's instruction-following in a future `meta/` pass if this recurs.
- **5h extra-usage quota lag observed once for ~12+ hours** (reported 100% used with a
  reset timestamp already ~12 hours in the past, well beyond the previously-documented
  10-15 minute lag) before clearing to 0%. Waited it out via a polling monitor rather than
  guessing at a shorter fixed delay; no other intervention needed.

### Needs attention
None — all five issues merged clean by the end of the sprint.

### Stats
- PRs merged: 5 (#223, #224, #225, #226, #227), plus this sprint's container PR
- Repair rounds: #216 — 0; #220 — 0; #221 — 1 (real bug); #169 — 0; #136 — 0
- Quota-hit recoveries: 5 (all resumed via nudge, no discarded work)
- Follow-up issues filed: none this sprint
- Total orchestration cost: ~$27.26 across 13 spawned sessions (8 opus impl/repair/
  investigation, 5 sonnet review)
