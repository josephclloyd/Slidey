# Sprint 28 — 2026-07-15

Started: 2026-07-15T00:00
Status: shipped

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 261 | Check Local Adjustments brush for the same Y-axis mask inversion as Object Removal | SlideshowView+LocalAdjustments.swift | opus | — |
| 262 | Break up the Edit menu into submenus | SlideyApp.swift (EditMenuCommands) | opus | — |
| 259 | Add in-app documentation for AI/editing tools to the Help menu | KeyboardShortcutsView.swift, possibly SlideyApp.swift (HelpMenuCommands) | opus | #262 |

No meta-labelled issues open this cycle. All 3 open issues from `josephclloyd` are
included — thin backlog again (only 3 candidates), same shape as Sprint 27.

## Notes per issue

**#261 (Local Adjustments Y-flip, no dependency):** Already confirmed real by Joe via
manual testing (see his 2026-07-15 comment on the issue) — this is a fix, not an
investigation. The exact bug and fix are known from #219/PR #260's Y-axis inversion:
`viewToImagePixel()` in `SlideshowView+LocalAdjustments.swift` computes
`py = norm.y * maskHeight` directly from a top-down normalized coordinate into a
Quartz-native (bottom-up) `CGContext` with no flip, identical to the pre-fix
`objectRemovalViewToImagePixel()`. Fix is the same one-line change:
`py = (1 - norm.y) * maskHeight`. Flag this directly to the impl session — don't have it
re-derive the diagnosis from scratch, just verify it also displays correctly (the mask is
consumed via `CIBlendWithMask`/CoreImage rather than a discrete on-screen preview, so
confirm the effect actually lands in the painted area post-fix, not just that the fix
compiles). Isolated to one extension file — no conflict with #262 or #259.

**#262 (Edit menu submenus, no dependency, placed first among the SlideyApp.swift
pair):** `EditMenuCommands` (`SlideyApp.swift:434-739`) is ~78 buttons/dividers across
~305 lines in one flat CommandGroup. The issue's own proposal has a concrete first-pass
grouping (Enhance / Denoise & Cleanup / Retouch / Geometry / Tone / Object Removal /
Batch & Copy) — good starting point, impl session can adjust if a cleaner grouping
emerges. Hard requirement: every existing keyboard shortcut must survive unchanged: verify
against CLAUDE.md's key binding registry before and after. Placed ahead of #259 per the
issue's own note ("fixing this one first would make #259's job easier") and because #259
may also touch `SlideyApp.swift`'s adjacent `HelpMenuCommands` struct if it adds a new Help
menu item — serializing avoids a same-file conflict.

**#259 (Help menu docs, blocked by #262):** Two design options in the issue: expand
`KeyboardShortcutsView` with per-tool descriptions, or add a separate `Help > Tools Guide`
window. Either is fine — impl session's call. Content must specifically call out the
scope differences within the three easily-confused tool groups the issue names: the
denoise family (classical Denoise vs JPEG Cleanup vs AI Grain Reduction), the retouch
family (Face Restore vs Red-Eye Removal vs Background Removal), and note Colorize's
grayscale/B&W expectation. If #262's submenu grouping has landed by the time this runs,
consider whether the new groupings suggest a natural per-submenu doc structure — not
required, just worth a glance.

## Excluded

None — all 3 open `josephclloyd` issues included.

## Notes

- `SlideshowView.swift` is down to ~3,369 lines after Sprint 27's extraction work
  (`SlideshowView+NotificationHandlers.swift` split) — comfortably under both the
  introspection skill's 2,000-line *concern* threshold... actually still over it, but well
  under SwiftLint's 3,500-line *error* threshold, which is the one that actually blocks
  CI. No issue this sprint touches `SlideshowView.swift`'s body directly, so no immediate
  risk of re-tripping the type-checker timeout or file-length error this cycle.
- None of this sprint's 3 issues touch `SlideshowView.swift` at all — first sprint in a
  while where the hot-file rule doesn't come into play. The real conflict risk this sprint
  is `SlideyApp.swift` (#262 and possibly #259), handled via the `addBlockedBy` edge above.
- Sprint 28 doesn't end in 7 — no introspection audit due this cycle.

## Results

Released: v1.27 — 2026-07-15

### Shipped
- #261 Local Adjustments Y-axis mask inversion — PR #264, 0 repair rounds. Confirmed
  latent bug, same fix as #219/PR #260's Y-flip (`py = (1 - norm.y) * maskHeight` in
  `viewToImagePixel()`). Session-only state, no persisted-data migration concern.
- #262 Break up the Edit menu into submenus — PR #265, 1 repair round. `EditMenuCommands`
  reorganized into 5 groups (Enhance / Denoise & Cleanup / Tone & Color / Retouch /
  Geometry); all 49 keyboard shortcuts verified preserved by the impl session's own
  before/after diff. Repair round wasn't a real defect — see Deviations.
- #259 Add in-app documentation for AI/editing tools to the Help menu — PR #267, 0 repair
  rounds (clean on first real review — see Deviations for the quota-driven false start).
  New `Help > Tools Guide` window; explicitly documents the three easily-confused tool
  groups (denoise family, retouch family, Colorize's grayscale expectation) called out in
  the issue. Impl session hit a mid-session quota cutoff after finishing implementation
  but before committing — recovered orchestrator-side (verified build, ran full test
  suite, committed/pushed/opened PR).

### Also filed this sprint
- #266 — Flaky test: `SlideshowControllerTests.testLoopDisabledStopsAtLastImage`.
  Surfaced during #259's recovery; confirmed unrelated to that PR's diff (passed in
  isolation on clean `main`, passed again on full-suite retry with the same changes
  present) before filing rather than blocking on it.
- #268 — Add on-image keyboard shortcuts overlay (upper-right corner, toggleable). Filed
  per Joe's request mid-sprint. Scoping note: single-letter key bindings a-z are now
  completely exhausted (verified against `handleCharacterKeyPress` directly) — the new
  toggle will need a modifier combination.

### Deviations from plan
- **#262's "repair round" was a false positive, not a real defect** — a bundle-detection
  case. #261 and #262 were spawned in parallel from the same base commit; #262's impl
  session independently discovered and fixed the identical Local Adjustments Y-flip bug
  that #261 was separately assigned to fix. #261 merged first, so by the time #262 reached
  review, review correctly flagged the duplicate/undocumented change (reviewer had no way
  to know #261 had already landed it). Resolved by merging `origin/main` into #262's
  branch, which made the now-identical hunk disappear — no actual code fix needed, just a
  rebase. Sent the repair session direct context about this (per run.md's plan-time-risk
  pattern, adapted for a review-time finding) rather than letting it rediscover the
  situation from the review comment alone.
- **Quota hit three times** — once a monthly extra-usage warning (85.2%, Joe chose to
  proceed), once a five-hour-window warning before spawning #259 (93%, Joe chose to
  proceed anyway), then two genuine review-spawn failures for #259 (0 tokens each) as the
  5h window fully exhausted, followed by a real ~30-minute wait for the reset. The new
  `review_round_retry` fix from Sprint 27's retro worked correctly both times — confirmed
  via `phase_state_get` that `review_round` stayed at 1 through both failed attempts
  rather than advancing toward the 2-round cap. First validation of that fix under real
  conditions.
- **Daemon was unstable at the very start of the run phase** — `mcx status` showed a fresh
  daemon restart with servers stuck in `connecting` state, and `mcx monitor` failed twice
  with "Was there a typo in the url or port?" before a `mcx restart` and a brief wait
  stabilized it (uptime climbing normally, all 8 servers connected). Not something the
  orchestrator caused; flagging in case it recurs — the fix was simply not spawning
  anything until `mcx status` showed a stable, climbing uptime with `_claude`/`_mock`/
  `_site` all `connected`, not `connecting`.

### Needs attention
None — all three planned issues merged, no open PRs.

### Stats
- PRs merged: 3 (#264, #265, #267)
- Issues filed: 2 (#266, #268 — open, backlog)
- Repair rounds: #261 — 0; #262 — 1 (bundle dedup, not a real defect); #259 — 0
- Quota-hit recoveries: 3 (2 "proceed anyway" decisions at 80%+ thresholds, 1 genuine
  wait for the 5h reset with 2 failed retry attempts along the way)
- Daemon instability recoveries: 1 (start-of-run monitor connection failures)
- Total orchestration cost: ~$4.51 across 10 spawned sessions (4 opus impl/repair, 6
  sonnet review — 2 of the 6 review attempts failed instantly on quota and cost $0),
  plus direct orchestrator work for #259's quota recovery
