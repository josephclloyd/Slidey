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
- **Image edit compositing** — `setDisplay(base:for:)` in `SlideshowView` is the single path for committing a new edited NSImage. It clears `effectImages[url]`, reapplies any active photo effect, and sets `currentDisplayImage`. All edit commit functions (sharpen, smooth, JPEG cleanup, upscale) must route through this helper so photo effects stay in sync. Do not assign `currentDisplayImage` directly after an edit.
- **Key binding registry** — keys already bound in `handleCharacterKeyPress`: `a`=enhance, `A`=remove-enhance, `m`=smooth, `M`=remove-smooth, `q`=jpeg-cleanup, `h`=sharpen, `H`=remove-sharpen, `u`=upscale-2x, `⌥U`=upscale-4x, `U`=remove-upscale, `s`=scale-to-native, `f`=scale-to-fill, `r`=rotate-CW, `R`=rotate-CCW, `n`=show-filename, `x`=toggle-favourite, `v`=favourites-only, `t`=thumbnails, `i`=image-info, `z`=smart-zoom, `/`=keyboard-shortcuts, `d`=debug-window, `j`=random-jump, `b`=before/after-preview, `e`=adjustments-hud, `E`=curves-hud, `c`=flip-H, `C`=flip-V, `p`=face-restore, `P`=remove-face-restore, `g`=red-eye-removal, `G`=remove-red-eye, `k`=background-removal, `K`=restore-background, `l`=artifact-removal, `L`=restore-artifacts, `o`=colorize, `O`=remove-colorization, `w`=crop, `W`=remove-crop, `y`=straighten-HUD, `Y`=remove-straighten, `⌥Y`=perspective-correction, `0`=clear-rating, `1`-`5`=set-rating. Menu-only bindings: `⌃⌘F`=toggle-fullscreen, `⌘+`/`⌘-`=zoom-in/out. Escape exits fullscreen or cancels active HUD/crop/upscale (does not enter fullscreen). Check this list before adding a new binding — SwiftLint `cyclomatic_complexity` (threshold ~50) will also fail if `handleCharacterKeyPress` gets too large.

## Gotchas

- The `external/` submodules (Real-ESRGAN, ncnn) are registered in git config but **not initialized** — the directory is empty. The binary is committed directly in `Resources/`. Do not attempt to initialize submodules.
- `MACOSX_DEPLOYMENT_TARGET = 15.0`. No `@available` guards are needed — every API used is macOS 15-compatible.
- `CODE_SIGNING_ALLOWED=NO` is required for `xcodebuild` CLI builds. Omitting it causes a codesign failure in non-interactive environments.
- **App Sandbox** is on. Features that need filesystem access beyond the user-selected directory require additional entitlements — don't add broad access entitlements without discussion.
- `SlideshowView.swift` uses `.onKeyPress` for Space, 't', etc. Key equivalents in `Commands` structs for the same keys are intentionally **commented out** — `.focusable()` takes priority and the key would be swallowed before the menu fires. See the `SlideshowMenuCommands` comment.
- **SlideshowView type-checker timeout**: Xcode 16.3's type-checker fails on deeply nested `ModifiedContent<..., ...>` chains. The body is structured as: `@ViewBuilder private var emptyStateContent/imageDisplayContent/overlayViews` → `private var coreView: some View` (ZStack + onChange/focusable/onKeyPress chain) → `var body` (coreView + onReceive chain). Any branch that adds to `overlayViews` or `coreView` may push over the limit and break CI. If CI fails at a line in `body` or `coreView` with "unable to type-check in reasonable time", the fix is to extract more content into a `@ViewBuilder private var` and/or split the `coreView` modifier chain further.
- **SwinIR / Core ML inference cannot be truly cancelled or force-terminated from app code.** `runSwinIRInference()` (shared by Artifact Removal and JPEG Cleanup — this is a JPEG-compression-blocking-artifact remover, not a general-purpose denoiser; the model is specifically trained for ~quality-40 JPEG artifacts, so don't expect a strong visual effect on images that weren't JPEG-blocky to begin with) uses `MLModelConfiguration().computeUnits = .cpuAndGPU`, not `.all` — requesting the Neural Engine (`.all`) can trigger an `ANECompilerService.xpc` JIT-compile stall lasting 100+ minutes at ~100% CPU, observed directly on this exact model. A load timeout (~30s) bounds how long the *app* waits and resets UI state on timeout, and a cancellation token is checked between tiles so a user Cancel stops further work — but neither can interrupt a single in-flight `MLModel(contentsOf:)` or `model.prediction()` call. A timed-out or cancelled operation can leave an orphaned background task (and, in the ANE-stall case, an orphaned root-owned `ANECompilerService.xpc` process outside the app's control) still consuming CPU until it organically finishes. If you're touching this code: never reintroduce `.all` compute units here without re-confirming the ANE stall doesn't reproduce, and don't assume "cancelled" means "stopped" — it means "the app stopped waiting."
- **Raw Core ML model output must be sanitized before `Int(Float)` conversion.** Swift's `Int(_:)` traps (crashes) on NaN/infinite Float input — `min`/`max` clamping *after* the `Int()` call does not protect against this, since the trap happens during the conversion itself, before the clamp ever runs. Any code converting raw model output (SwinIR tile blending, CodeFormer face restoration, DDColor colorization) to pixel bytes must check `.isFinite` (or otherwise sanitize) *before* calling `Int(...)`, not after. Hit as a real crash (`Fatal error: Float value cannot be converted to Int because it is either infinite or NaN`) in the SwinIR tile-blending path; fixed there, but the same unsafe `Int(min(255, max(0, ...)))`-after-conversion pattern exists elsewhere in `SlideshowView+AIEdits.swift` (face restore, colorize) and hasn't been audited yet.

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
