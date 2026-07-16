# Sprint 29 — 2026-07-15

Started: 2026-07-15T00:00
Status: shipped

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 266 | Flaky test: SlideshowControllerTests.testLoopDisabledStopsAtLastImage | SlideyTests/SlideshowViewTests.swift, possibly SlideshowController.swift | opus | — |
| 268 | Add on-image keyboard shortcuts overlay (upper-right corner, toggleable) | SlideshowView.swift | opus | — |
| 269 | ⌘Z should undo the last photo edit, not just rename/move-to-trash | SlideshowView.swift and extensions (many edit-commit functions) | opus | #268 |

No meta-labelled issues open this cycle. All 3 open issues from `josephclloyd` included.

## Notes per issue

**#266 (flaky test, no dependency):** `testLoopDisabledStopsAtLastImage` uses real
`DispatchQueue.main.asyncAfter` timing (0.05s interval, 0.5s wait, 2.0s expectation
timeout) — classic flaky-test shape under system load, not obviously a
`SlideshowController` logic bug. Confirmed unrelated to any recent diff (passed in
isolation on clean main, passed again on a full-suite retry) during Sprint 28. Fix may be
test-only (more deterministic polling instead of wall-clock timing) or may touch
`SlideshowController.swift` if it needs an injectable clock/scheduler for determinism —
either way, isolated from `SlideshowView.swift`, no conflict with #268/#269.

**#268 (shortcuts overlay, no dependency, placed first among the SlideshowView.swift
pair):** New on-image overlay + dedicated toggle key. Flagged during planning: single-letter
key bindings a-z are completely exhausted (verified against `handleCharacterKeyPress`
directly) — will need a modifier combination. `imageInfoOverlay`
(`SlideshowView.swift:335-374`) is the direct precedent to follow for positioning/styling.
Placed ahead of #269 since both touch `SlideshowView.swift` and this one is smaller.

**#269 (undo, blocked by #268):** Bigger scope — the app already has a working
`NSUndoManager`-based undo system (`myWindow?.undoManager?.registerUndo`, used today only
for rename/move-to-trash, `SlideshowView.swift` ~2636/~2738), but no photo-edit function
registers with it. This issue extends that existing mechanism to edits rather than
building a new one. Flagged for the impl session: check whether #235's
`collectCopyableEdits(from:)`/`applyCopiedEdits(_:to:)` helpers
(`SlideshowView+BatchApply.swift`, `SlideshowView+CopyPasteAdjustments.swift`) can be
reused for the snapshot/restore mechanism, since they already solve "capture this image's
full edit state" for a different feature. Given the number of distinct edit-commit
functions involved (~20+, per CLAUDE.md's key binding registry), this is the highest-touch
issue this sprint on `SlideshowView.swift` — serialized behind #268 to avoid a same-file
conflict, and impl session should watch for the type-checker/file-length gotchas already
documented in CLAUDE.md if this pushes `SlideshowView.swift` size up again.

## Excluded

None — all 3 open `josephclloyd` issues included.

## Notes

- Sprint 29 doesn't end in 7 — no introspection audit due this cycle.
- Backlog is now down to 0 additional untracked issues beyond this sprint's 3 (after
  #266/#268 were filed in Sprint 28's retro and #269 was filed during this planning
  session, per Joe's live request). Next sprint's planning will likely need fresh issues
  drafted from scratch unless Joe files more.

## Results

Released: v1.28 — 2026-07-15

### Shipped
- #266 Flaky test: `SlideshowControllerTests.testLoopDisabledStopsAtLastImage` — PR #271,
  0 repair rounds. Turned out to be a real production bug, not just test flakiness: a
  missing `deinit` let `SlideshowController`'s timer keep firing on the RunLoop after
  dealloc even with a `weak self` reference — a genuine resource leak. Fixed at both
  layers (production `deinit` + deterministic test-side `stop()` calls).
- #268 Add on-image keyboard shortcuts overlay — PR #272, 0 repair rounds. Toggled with
  the previously-unbound `/` key (confirmed no conflict with `⌘/`'s existing full-sheet
  binding). `handleCharacterKeyPress` now at 47/~50 cases — approaching but not yet
  breaching the SwiftLint cyclomatic-complexity threshold.
- #269 ⌘Z undo support for all photo edits — PR #273, 0 repair rounds. Extended the
  existing `NSUndoManager` mechanism (previously only rename/move-to-trash) to every edit
  tool via a new `SlideshowView+Undo.swift`: snapshots full per-image edit state
  (including cached images, not just parameters, so undo doesn't re-run expensive AI
  models) before each edit, registers a redo on undo, and gets multi-level undo/redo for
  free from `NSUndoManager`'s native stack. Biggest issue this sprint (104 turns, ~$6.79)
  and the only one with real quota friction — see Deviations.

### Also filed this sprint
- #274 — Red-Eye Removal doesn't correct anything (Joe's report, root cause found during
  triage: `CIRedEyeCorrection` needs an `inputEyes` parameter that the code never sets —
  `VNDetectFaceRectanglesRequest` only returns face bounding boxes, not eye positions, so
  the filter silently no-ops while the app still marks the edit as applied).
- #275 — Shortcuts overlay (#268) is missing most editing-tool shortcuts (Joe's report;
  the overlay's condensed "Enhance" section covers only 4 of the app's ~20 edit tools).

### Deviations from plan
- **Extra-usage budget climbed to 89.1%** ($4100/$4600) at the start of this sprint, up
  from 85.2% at the start of Sprint 28 — flagged to Joe before spawning anything; he chose
  to proceed. Five-hour window also hit 90% right before #269 (the sprint's biggest issue)
  was due to start — flagged again, Joe chose to proceed anyway.
- **#269's first impl attempt hit genuine quota exhaustion almost immediately** (4 turns,
  $0.13, zero commits — a true zero-progress case, nothing to recover). Five-hour window
  needed a real ~3-hour wait for its full reset this time (longer than Sprint 28's ~30min
  wait) — scheduled periodic wakeups rather than one long wait. Resumed cleanly once
  `quota_status` showed 0% utilization; #269 then completed in one full session (104
  turns) with no further quota issues.
- **The persistent monitor task silently expired after its 1-hour timeout** during the
  ~3-hour quota wait, requiring a restart before #269's session.result event could be
  received. Not noticed until manually checking — worth remembering that a long quota
  wait will always outlast a single Monitor call's timeout window.
- **Two impl sessions ran concurrently in the same shared main checkout** (#266 and #268,
  per the `--worktree`-doesn't-create-a-real-worktree gotcha) — #266's own session flagged
  seeing "unrelated files being re-modified" mid-run (almost certainly #268's concurrent
  edits). Both PRs' diffs were verified clean afterward (no cross-contamination, no
  overlapping files) — the rule of thumb "different files touched → safe to run in
  parallel" held, but it's worth noting the sessions can observe each other's changes
  mid-flight even when the final diffs stay clean.

### Needs attention
None — all three planned issues merged, no open PRs.

### Stats
- PRs merged: 3 (#271, #272, #273)
- Issues filed: 2 (#274, #275 — open, backlog)
- Repair rounds: 0 across all three issues — cleanest sprint yet on that metric
- Quota-hit recoveries: 2 (one instant zero-progress failure, one genuine ~3h wait for
  the five-hour window to reset)
- Total orchestration cost: ~$14.61 across 7 spawned sessions (4 opus impl — one of which
  cost $0.13 for a zero-progress quota failure before #269's real attempt — 3 sonnet
  review)
