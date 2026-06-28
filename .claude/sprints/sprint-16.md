# Sprint 16 — 2026-06-28

Started: 2026-06-28T00:00:00Z
Status: done

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 153 | Info overlay: show upscaled dimensions | SlideshowView.swift | opus | — |
| 130 | Persist per-image edits (rotation, enhance, smooth) across launches | SlideshowView.swift | opus | #153 |
| 131 | Open in Preview / Open With… | SlideshowView.swift, SlideyApp.swift | opus | #130 |
| 140 | Always-on-top / float above other windows | SlideyApp.swift, SlideshowView.swift | opus | #131 |

## Excluded

- #102 — Export filtered set: medium-large feature; sprint 17 candidate
- #134 — Keyboard shortcut help overlay: large overlay UI; sprint 17
- #100 — Star/rate images: EXIF writing is complex; warrants own sprint
- #141, #133, #135–#139, #129 — Sprint 17+ candidates

## Notes

- All 4 issues touch SlideshowView.swift — serialized via blocked-by chain: #153 → #130 → #131 → #140
- #131 and #140 also share SlideyApp.swift — serialized by same chain
- #153 is the quickest (two lines of overlay text) — fast first merge, unblocks chain
- #130 mirrors the existing favouriteImages persistence pattern in SlideshowView.swift
- #131 and #140 both follow the standard notification → API call pattern
- Author trust filter: all issues filed by josephclloyd ✓
- No open bugs; sprint 15's #149 regression was fixed in PR #152

## Results

Released: v1.15 — 2026-06-28

### Shipped
- #149 Fix 2x upscale corruption (Core ML backend, PR #152) — pre-sprint carry-over
- #153 Info overlay: show upscaled pixel dimensions with arrow (PR #155)
- #130 Persist per-image edits (rotation, enhance, smooth) across launches (PR #156)
- #131 Open in Preview / Open With… in File menu (PR #157)
- #140 Always-on-top / Float Above Other Windows toggle (PR #158)

### Needs attention
(none)

### Stats
- PRs merged: 5 (1 pre-sprint bug fix + 4 sprint issues)
- Repair passes: 1 (#130 PR #156 — added `[url]` capture list + guard to async block after review)
- mcx sessions: bypassed (Not Logged In error); implemented directly in main conversation
- CI wall time per PR: ~75s
