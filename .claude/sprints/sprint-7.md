# Sprint 7 — 2026-06-04

Started: 2026-06-04T00:00:00Z
Status: complete

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 46 | Notifications.swift enum | `SlideshowView.swift`, `SlideyApp.swift`, new `Notifications.swift` | opus | — |
| 47 | Update CLAUDE.md and README | docs only | opus | — |
| 48 | Home/End keys to jump to first/last image | `SlideshowView.swift` | opus | #46 |
| 49 | Remember window size and position | `SlideyApp.swift` | opus | #46 |
| 50 | Pixel dimensions + file size in info overlay | `SlideshowView.swift` | opus | #48 |

## Excluded

- D (Slideshow loop mode) — already implemented: `nextImage()` uses `% imageURLs.count`, wraps naturally.

## Notes

- Sprint 7 = introspection sprint. Findings that drove this backlog:
  - SlideshowView.swift at 1,911 lines (up from 1,558 at sprint 1; threshold ~2,000)
  - 47+ hardcoded `NSNotification.Name("...")` string literals across SlideshowView + SlideyApp → issue #46
  - `MusicManager.swift` (343 lines) is a fully-shipped 5th source file not documented anywhere → issue #47
  - Session-state dictionaries at exactly 5 keys — at threshold but not over it; no action needed yet
- Parallelism: #46 and #47 can run simultaneously. Once #46 merges, #48 and #49 can run in parallel. #50 unblocks after #48 merges.
- Author trust filter: all issues filed by `josephclloyd` ✓.

## Results

Released: v1.7 — 2026-06-04

### Shipped
- #52 Update CLAUDE.md and README — PR #52, merged 2026-06-04T20:44:21Z. Added MusicManager.swift to architecture docs, updated LOC count, added missing keyboard shortcuts (i, music menu) to README.
- #53 Notifications.swift enum — PR #53, merged 2026-06-04T20:44:31Z. Replaced 23 hardcoded `NSNotification.Name("...")` string literals with type-safe `NSNotification.Name` static constants in new `Notifications.swift`.
- #54 Home/End keys to jump to first/last image — PR #54, merged 2026-06-04T20:50:02Z. Home jumps to index 0, End jumps to last image, via `.onKeyPress` in SlideshowView.
- #55 Remember window size and position — PR #55, merged 2026-06-04T21:26:46Z. `NSWindow.setFrameAutosaveName("MainWindow")` in AppDelegate; AppKit handles persistence and off-screen recovery automatically.
- #56 Pixel dimensions + file size in info overlay — PR #56, merged 2026-06-04T21:29:14Z. `i` overlay now shows pixel dimensions and file size loaded off the main thread via `Task.detached` + `MainActor.run`.

### Stats
- PRs merged: 5 (#52–#56)
- Total cost: ~$5.50 (impl #46 $2.10 + impl #47 $0.60 + impl #48 $0.59 + impl #49 $0.74 + impl #50 $0.67 + reviews $0.81)
- CI wall time: ~2m per PR
- Notable: sessions ran in the main worktree (not separate worktrees despite `--worktree` flag), causing branch drift after each session — recovered with `git checkout main` after each completion. `Closes #N` was missing from 3 of 5 PR bodies (added manually — routine step).
