# CLAUDE.md

Slidey — a native macOS SwiftUI slideshow app for viewing images with enhancement and display controls.

## Build

```bash
# From the repo root:
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO

# Run the built app:
open ~/Library/Developer/Xcode/DerivedData/Slidey-*/Build/Products/Debug/Slidey.app
```

Build is fast (~1–2s incremental, ~15s clean). CI runs both `xcodebuild build` and `xcodebuild test`. Functional validation beyond what the test suite covers is manual (launch the app, exercise the feature).

## Requirements

- macOS 15.0+, Xcode 16.0+
- App Sandbox enabled with `user-selected.read-write` and `bookmarks.app-scope` entitlements

## Architecture

Five source files (~3,000 LOC); test target in `SlideyTests/`:

```
slidey/
  SlideyApp.swift         App entry, AppDelegate, menus, Settings scene
  SlideshowView.swift     Main UI (~1900 lines): image display, zoom/pan, key handling,
                          thumbnails, upscale progress, crossfade transitions,
                          EXIF/info overlay, clipboard copy — all @State + @StateObject
  ImageLoader.swift       Directory scan, sort, decode, cache, DispatchSource watcher
  MusicManager.swift      Background music via MusicKit (song, playlist, shuffle modes)
  RecentDirectories.swift Security-scoped bookmark persistence for recent folders
  Resources/
    realesrgan-ncnn-vulkan  Pre-built AI upscaling binary (26 MB, committed directly)
    models/                 Real-ESRGAN model files
```

**Hot file:** `SlideshowView.swift`. Most new features touch it. PRs that both add a feature and refactor `SlideshowView` simultaneously tend to conflict with sibling branches — keep changes focused.

## Key Patterns

- **Menu commands** fire `NotificationCenter` posts (`NSNotification.Name("EnhanceImage")` etc.). `SlideshowView` subscribes with `.onReceive`. This decouples the menu from the view state.
- **Per-image session state** (rotate, enhance, smooth, upscale, zoom) is keyed by `URL`, not index, so it survives directory rescans and index shifts.
- **Security-scoped bookmarks** are required to reopen recent directories across launches (App Sandbox). `RecentDirectories` manages start/stop access.
- **AI upscaling** spawns `realesrgan-ncnn-vulkan` as a subprocess; stderr lines are parsed for percentage progress. The process can be terminated on Cancel/Escape.
- **Thumbnail cache** is `NSCache` (500-entry LRU). Thumbnails generated via `CGImageSourceCreateThumbnailAtIndex` — uses embedded EXIF thumbnails when available, never decodes the full bitmap.
- **Background music** via `MusicManager` (@MainActor ObservableObject). Uses MusicKit `ApplicationMusicPlayer`. Modes: single song, playlist, shuffle. Persists selection in `@AppStorage`. Controlled via Music menu commands fired through `NotificationCenter`.
- **Crossfade transitions** between images are optional (`@AppStorage("transitionsEnabled")`), with configurable duration.

## Gotchas

- The `external/` submodules (Real-ESRGAN, ncnn) are registered in git config but **not initialized** — the directory is empty. The binary is committed directly in `Resources/`. Do not attempt to initialize submodules.
- `MACOSX_DEPLOYMENT_TARGET = 15.0`. No `@available` guards are needed — every API used is macOS 15-compatible.
- `CODE_SIGNING_ALLOWED=NO` is required for `xcodebuild` CLI builds. Omitting it causes a codesign failure in non-interactive environments.
- **App Sandbox** is on. Features that need filesystem access beyond the user-selected directory require additional entitlements — don't add broad access entitlements without discussion.
- `SlideshowView.swift` uses `.onKeyPress` for Space, 't', etc. Key equivalents in `Commands` structs for the same keys are intentionally **commented out** — `.focusable()` takes priority and the key would be swallowed before the menu fires. See the `SlideshowMenuCommands` comment.

## Workflow

Issues are tracked in GitHub Issues. The backlog comes from the README "Roadmap / TODO" section.

Memory files in `.claude/memory/` must be committed and pushed when changed — they are
git-tracked and synced across machines via a symlink to `~/.claude/projects/<slug>/memory/`.

Implementation branches follow the pattern `<short-description>` (e.g. `move-to-trash`, `auto-open-recent`).

PRs need:
1. A clean `xcodebuild build` (CI checks this automatically)
2. A description listing what changed and a manual test checklist
3. Joe's review and merge

`SlideyTests/` contains unit tests across 4 test files. CI runs `xcodebuild test` on every push and PR. The PR description's manual test checklist supplements the automated tests — it covers UI behaviour and edge cases that the test suite doesn't reach.

**New features must include tests where possible.** When implementing an issue:
- Logic in `ImageLoader.swift` and `SlideshowController.swift` is unit-testable — add tests in the corresponding test file.
- Pure model/state changes (enum cases, AppStorage defaults, notification names) are testable — add them to `SlideyAppTests.swift`.
- SwiftUI view state in `SlideshowView.swift` is harder to test directly — cover the underlying controller/loader logic instead, and rely on the manual test checklist for UI behaviour.
- If a feature is genuinely untestable (pure UI wiring with no extractable logic), note that explicitly in the PR description rather than skipping silently.
