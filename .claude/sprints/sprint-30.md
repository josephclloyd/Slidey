# Sprint 30 — 2026-07-16

Started: 2026-07-16T00:00
Status: shipped

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

## Results

Released: v1.29 — 2026-07-16

### Shipped
- #275 Shortcuts overlay is missing most image-editing tool shortcuts — PR #277, 0 repair
  rounds. Reorganized into a two-column layout (left: Navigate/Display/Enhance/Rate;
  right: Denoise & Cleanup/Retouch/Geometry, mirroring #262's Edit menu groupings). All
  key bindings verified against `handleCharacterKeyPress` and `SlideyApp.swift`.
- #274 Red-Eye Removal doesn't correct anything — PR #278, 0 repair rounds. My original
  triage diagnosis (add `inputEyes` to `CIRedEyeCorrection`) turned out to be wrong in a
  useful way: the impl session discovered `CIRedEyeCorrection` is actually
  `CICategoryApplePrivate` with no public typed API — its only real parameter
  (`inputCorrectionInfo`) is an undocumented `NSDictionary` format, not `inputEyes` at
  all. Rather than reverse-engineering a private API, it implemented a manual pixel-level
  correction: `VNDetectFaceLandmarksRequest` for eye localization, red-ratio threshold
  detection with radial-fade correction in a known-format RGBA bitmap, plus a "No
  Red-Eye Detected" alert distinguishing "no faces" from "faces but no red-eye" (matching
  the existing `showNoFaceAlert` pattern). A better outcome than the diagnosed fix would
  have produced.

### Post-merge fix (not part of the original plan)
Joe reported "No Red-Eye Detected" on a photo with clearly visible red-eye immediately
after #274/PR #278 merged — the review that approved #278 couldn't catch this since
neither the review session nor I can launch the app to visually verify detection actually
fires on a real photo. Root-caused directly (PR #279, not through the tracked-issue
pipeline, same posture as #219's post-merge fixes in Sprint 27): `redRatio = r/(g+b) > 1.5`
is too strict for real, compressed/blurred photos — a visibly red pixel like
`r=140,g=70,b=60` only scores ~1.08. Replaced with an absolute red-dominance test
(`r - max(g,b) > 25`), which also made the old upper-brightness bound redundant (a
white catchlight has ~0 red-dominance regardless of brightness) and dropped it. Flagged
clearly in the PR that the new threshold is still an unverified judgment call, not a
measured value — same "verify visually before fully trusting" caveat as #278 itself, now
twice in a row for this feature.

### Deviations from plan
- **`mcx` CLI/daemon protocol mismatch mid-sprint** — the daemon had auto-upgraded
  (1.12.1 → 1.14.6) while this session's client expected the old protocol, blocking every
  `mcx` command including basic queries. Fixed with Joe's explicit go-ahead via
  `mcx daemon reload --force` (flagged the risk clearly first: 22 sessions would be
  "orphaned," all confirmed to be stale idle records from sprints 27-30, not real
  in-flight work — actual work lives in git/GitHub regardless of daemon state).
- **`.mcx.lock` invalidated by the same upgrade** — newer `mcx` computes phase-file
  content hashes differently, so `mcx phase run` refused to work even though no phase
  file content had actually changed (confirmed via `git diff` — clean). Regenerated via
  `mcx phase install` and pushed the resulting `.mcx.lock`-only diff directly to `main`
  per run.md's tooling-blocked exception (confined to `.mcx.lock`, normal PR flow was
  verifiably blocked by the exact thing being fixed).
- **#274's review needed two quota-retry cycles**, one of which spanned the daemon
  upgrade/protocol-mismatch incident above — genuinely tangled together rather than two
  clean separate incidents. `review_round_retry` correctly prevented double-counting
  through both attempts.

### Needs attention
Both planned issues merged. One follow-on: **PR #279** (red-eye detection threshold fix)
is open, not yet merged — needs Joe's manual verification against the photo that
triggered the report before merging, since neither the review pipeline nor direct
orchestrator work can visually confirm detection accuracy without launching the app.

### Stats
- PRs merged: 2 (#277, #278), plus 1 direct-to-main tooling fix (`.mcx.lock`
  regeneration, no application code); 1 more open awaiting Joe's verification (#279)
- Repair rounds: 0 across both planned issues
- Quota-hit recoveries: 2 (both for #274's review)
- Infrastructure incidents: 1 (mcx daemon/CLI protocol mismatch, resolved with a forced
  reload)
- Total orchestration cost: ~$2.62 across 6 spawned sessions (2 opus impl, 4 sonnet
  review — 2 of the review attempts failed instantly on quota, ~$0.29 combined)
