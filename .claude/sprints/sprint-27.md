# Sprint 27 — 2026-07-14

Started: 2026-07-14T00:00
Status: planned

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

(filled in by run/review)
