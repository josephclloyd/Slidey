# Sprint 4 — 2026-05-29

Started: 2026-05-29T00:00:00Z
Status: complete

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 28 | Wire test suite into CI | `.github/workflows/build.yml` | opus | — |
| 31 | Background music: play Apple Music during slideshows | `SlideyApp.swift`, `SlideshowView.swift`, `Slidey.entitlements`, new `MusicManager.swift` | opus | — |
| 29 | Expand unit test coverage for core logic | `SlideyTests/` | opus | #28 |

## Excluded

| # | Title | Reason |
|---|-------|--------|
| — | — | All 3 open issues from josephclloyd included. |

## Notes

- #28 + #31 run in parallel (no shared files).
- #29 blocked by #28: want CI running the test suite before expanding it, so failures are visible on the PR.
- #31 is the largest issue this sprint. `com.apple.developer.musickit` entitlement requires App Store Connect registration for full Apple Music streaming; `media-library` entitlement covers local library access without ACS setup. CI passes either way (`CODE_SIGNING_ALLOWED=NO`). Impl session should use `media-library` first and add `musickit` as an additive capability.
- Author trust filter: #28, #29, #31 all filed by `josephclloyd`. ✓

## Results

Released: v1.4.0 — 2026-05-29

### Shipped
- #28 Wire test suite into CI — added `xcodebuild test` step to `build.yml`; all 29 existing tests now gate PRs
- #29 Expand unit test coverage — 42 new tests (72 total): extension filtering, all 7 sort comparators, upscale progress parsing, thumbnail cache eviction, RecentDirectories deduplication/trimming
- #31 Background music via Apple Music / MusicKit — new `MusicManager.swift` with song/playlist/shuffle/off modes, proper auth flow, `media-library` entitlement; music activates with images, pauses at welcome screen; track overlay on change

### Needs attention
(none)

### Stats
- PRs merged: 3 (#33, #34, #35)
- Total cost: ~$18.20 (impl $0.35+$3.31+$10.34 + review $0.59+$0.27+$0.41 + repair $0.57+$0.21 = ~$15.65 sessions + orchestration)
- CI wall time: ~2-3 min per PR
- Notable: rate limit hit mid-sprint; sessions recovered cleanly. GitHub Actions stopped triggering after multiple pushes — resolved by merge commit pushing a fresh webhook.
