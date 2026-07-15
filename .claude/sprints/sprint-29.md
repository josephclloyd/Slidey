# Sprint 29 — 2026-07-15

Started: 2026-07-15T00:00
Status: planned

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
