# Sprint 10 — 2026-06-15

Started: 2026-06-15T00:00:00Z
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 60 | Add SwiftLint to enforce style and catch common bugs | `.swiftlint.yml`, `.github/workflows/`, source files | opus | — |
| 80 | Expand ImageLoader test coverage | `ImageLoaderTests.swift` | opus | — |

## Excluded

- #79, #81, #82, #83, #84, #85 — all touch SlideshowView.swift; deferred until after #60 merges so SwiftLint fixes don't conflict

## Notes

- Wave 1 (parallel): #60 + #80 — no file conflicts; #80 touches only a test file
- #60 may modify source files to resolve violations, or opt them out via .swiftlint.yml — either way, SlideshowView.swift features must wait for it
- Author trust filter: all issues filed by `josephclloyd` ✓
