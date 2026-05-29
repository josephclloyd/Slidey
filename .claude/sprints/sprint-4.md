# Sprint 4 — 2026-05-29

Started: 2026-05-29T00:00:00Z
Status: planned

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
