# Sprint 38 — 2026-07-28

Started: 2026-07-28T18:30:00Z
Status: done

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 332 | Video playback (mov, mp4, m4v) inline with AVKit | ImageLoader.swift (extension scan, first-frame thumbnail), SlideshowView+Video.swift (new — VideoPlayerView, VideoPlayerController), SlideshowView.swift (minimal wiring: isVideoURL check, Space key, overlay) | opus | — |

## Excluded

- #325 Sync pan/zoom between compare panes — touches SlideshowView.swift; serialize after #332
- #326 Compare any two images — touches SlideshowView.swift; serialize after #332
- #328 Selective colour — touches SlideshowView.swift; serialize after #332
- #329 Multi-select — large scope, touches SlideshowView.swift; own sprint
- #334 Introspection findings — tech debt; address incrementally, not as a sprint issue

## Results

Released: v1.37 — 2026-07-28

### Shipped
- #332 Video playback (mov, mp4, m4v, mkv) inline with AVKit — `SlideshowView+Video.swift` (new, 219 lines), `VideoPlaybackTests.swift` (180 lines, 12 tests), first-frame thumbnails via `AVAssetImageGenerator`, Space key context-aware (play/pause vs slideshow toggle), mute button in HUD, slideshow auto-advance paused during playback, "editing not available" overlay

### Needs attention
(none)

### Stats
- PRs merged: 1 (#338)
- Total cost: ~$4.27 (impl $3.76, review $0.51)
- Repair rounds: 0
- CI wall time: ~2.5 min

## Notes

- **SlideshowView.swift line count is critical**: file is at 3,379 lines (121 from SwiftLint hard stop after Sprint 37). ALL video logic — `VideoPlayerController` (@Observable class wrapping AVPlayer), `VideoPlayerView` (SwiftUI view), and related helpers — must live in a new `SlideshowView+Video.swift`. SlideshowView.swift itself should receive at most ~20–30 lines of wiring (an `isVideoURL` computed var, the overlay guard, and the Space-key branch). Register the new file in `project.pbxproj` immediately or CI fails.

- **Space key**: Space is already bound to `toggleSlideshow()` (line 1354 in `handleCharacterKeyPress`). When a video is active, Space should toggle video play/pause instead. Implementation: add `@State var isVideoActive: Bool = false` on SlideshowView, and update the Space case to `if isVideoActive { videoController.togglePlayPause() } else { toggleSlideshow() }`.

- **`m` key is taken** (`m`=smooth, `M`=remove-smooth) — the issue text's suggestion to use `m` for mute is wrong. Do NOT add a mute key binding. Mute/unmute goes on a HUD button in `VideoPlayerView` only.

- **VideoPlayerController**: `@Observable` class (not `@StateObject`) wrapping `AVPlayer`. Owns playback state: `isPlaying`, `isMuted`. Looping via `AVPlayerLooper` or `NotificationCenter` observe of `.AVPlayerItemDidPlayToEndTime`. On video URL change: replace the current `AVPlayerItem`.

- **First-frame thumbnail**: `AVAssetImageGenerator` at time `.zero`, async, cached in `ImageLoader`'s existing thumbnail `NSCache`. This logic is unit-testable — add to `ImageLoaderTests`.

- **Extension scan**: add `["mov", "mp4", "m4v", "mkv"]` to `ImageLoader`'s allowed extensions. These must be included in the directory scan but skipped by all image-specific processing (enhance, crop, ML, etc.).

- **Slideshow auto-advance**: pause while a video is playing (same pattern as animated GIF in `SlideshowView+Animation.swift` — read that file for the exact pattern).

- **Editing tools unavailable for video**: show a subtle "Editing not available for video" overlay or disable the edit menu items when a video URL is current. Do NOT hide/restructure all controls — the issue text is explicit about this. A simple `.disabled(isVideoActive)` on edit menus plus a one-line text overlay is sufficient.

- **Navigation**: left/right arrow navigation continues to work normally; on navigation away from a video, pause it and release the `AVPlayer`.

- **Unit tests**: thumbnail extraction logic (`AVAssetImageGenerator` flow) and extension-scan inclusion in `ImageLoaderTests`. Video playback itself (AVPlayer behaviour) is not unit-testable; note this explicitly in the PR.
