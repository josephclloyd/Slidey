# Sprint 28 — 2026-07-15

Started: 2026-07-15T00:00
Status: planned

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
