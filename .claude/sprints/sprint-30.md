# Sprint 30 — 2026-07-16

Started: 2026-07-16T00:00
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 274 | Red-Eye Removal doesn't correct anything — missing inputEyes on CIRedEyeCorrection | SlideshowView+AIEdits.swift | opus | — |
| 275 | Shortcuts overlay is missing most image-editing tool shortcuts | SlideshowView.swift (shortcutsOverlay) | opus | — |

No meta-labelled issues open this cycle. Both open issues from `josephclloyd` included —
thin backlog again (only 2 candidates). No hot-file conflict: #274 is isolated to
`SlideshowView+AIEdits.swift`; #275 touches only the `shortcutsOverlay` computed property
in `SlideshowView.swift`, unrelated to anything #274 touches. Both run unblocked.

## Notes per issue

**#274 (red-eye bug, no dependency):** Root cause already diagnosed during triage (see
issue body) — `CIRedEyeCorrection` needs an `inputEyes` parameter that
`applyRedEyeOnCurrentImage()` never sets, so the filter silently no-ops while the app
still marks the edit as applied. Fix direction is spelled out in the issue: switch
`VNDetectFaceRectanglesRequest` to `VNDetectFaceLandmarksRequest` to get actual eye
points, convert to the `inputEyes` format, set it on the filter before reading
`outputImage`. Flag directly to the impl session: verify against a real photo with
visible red-eye that pixels actually change, not just that the code path runs without
error — this bug shipped originally because the code "succeeded" without producing a
visible effect, so a superficial check would miss a similarly-incomplete fix.

**#275 (shortcuts overlay gap, no dependency):** Extend the existing condensed overlay
(`shortcutsOverlay`, `SlideshowView.swift` ~378-425) to cover the editing tool families
called out as easily-confused (denoise family, retouch family) plus geometry tools.
#262's Edit menu submenu groupings (Enhance / Denoise & Cleanup / Tone & Color / Retouch /
Geometry) are the natural section structure to extend `shortcutsSection(...)` with.
Keep it a compact corner reference, not a full-screen list — issue explicitly allows a
more condensed single-line-per-tool format if the expanded content gets too tall.

## Excluded

None — both open `josephclloyd` issues included.

## Notes

- Sprint 30 doesn't end in 7 — no introspection audit due this cycle.
- Backlog is thin again (2 issues) — same shape as recent sprints. Extra-usage budget was
  at 89.1% ($4100/$4600) at the end of Sprint 29 with no confirmed reset date observed
  yet; worth checking `mcx call _metrics quota_status` before spawning and being prepared
  to flag it again if it's still elevated.
- No memory audit ran at the end of Sprint 29 (quota-exhausted); retro for this sprint
  should run a real one rather than skipping a second time in a row.
