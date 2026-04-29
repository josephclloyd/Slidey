# Slidey

A native macOS slideshow application for viewing images with powerful navigation, enhancement, and display controls.

## Features

- **Directory-based slideshow** - Select any folder and view all images as a slideshow
- **Fullscreen mode** - Automatic fullscreen when loading images
- **Auto-enhancement** - One-key image enhancement using Core Image filters
- **Image smoothing** - Reduce noise and pixelation with noise reduction filter
- **Image rotation** - Rotate images and remember orientation per image
- **Zoom controls** - Scale to native size or fill screen
- **Pan and zoom** - Navigate zoomed images with arrow keys
- **Recent directories** - Quick access to last 5 opened folders
- **Multiple windows** - Open multiple slideshows simultaneously
- **AI upscaling** - 4x AI-powered upscaling using Real-ESRGAN
- **Filename overlay** - Toggle display of the current image filename
- **Session memory** - Remembers rotations, enhancements, smoothing, and upscaling per session
- **Auto-advance slideshow** - Play / pause with Space; interval configurable in Settings

## Keyboard Shortcuts

### Navigation
- **Left/Right Arrow** - Previous/Next image
- **Any key** - Next image (when not zoomed)

### Display Controls
- **s** - Scale to Native Size (1:1 pixel ratio)
- **f** - Scale to Fill Screen (orientation-aware)
- **+** or **=** - Zoom in
- **-** - Zoom out

### Rotation
- **r** - Rotate 90° clockwise
- **Shift+R** - Rotate 90° counter-clockwise

### Enhancement
- **a** - Auto-enhance current image
- **Shift+A** - Remove enhancement
- **m** - Smooth current image (reduce noise/pixelation)
- **Shift+M** - Remove smoothing
- **u** - AI upscale image 4x (uses Real-ESRGAN)
- **Shift+U** - Remove upscaling

### Overlay
- **n** - Toggle filename overlay (lower-left corner)
- **d** - Toggle debug output window

### Slideshow
- **Space** - Play / Pause auto-advance (interval set in Settings)

### Window
- **Escape** - Toggle fullscreen (or cancel an in-progress upscale)
- **Command+N** - New window
- **Command+O** - Open directory
- **Command+,** - Settings…

### Pan (when zoomed)
- **Arrow keys** - Pan image in all directions

## Usage

1. Launch Slidey
2. Click "Select Directory" or press Command+O
3. Choose a folder containing images
4. Navigate through images using arrow keys
5. Apply enhancements, rotations, or scaling as needed

## Supported Formats

- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- BMP (.bmp)
- TIFF (.tiff)
- HEIC (.heic)
- WebP (.webp)

## Menu Commands

### File Menu
- **New Window** (Command+N) - Open a new slideshow window
- **Open...** (Command+O) - Select a directory
- **Recent Directories** - Access recently opened folders

### Edit Menu
- **Auto-Enhance Image** (a)
- **Remove Enhancement** (Shift+A)
- **Smooth Image** (m)
- **Remove Smoothing** (Shift+M)
- **AI Upscale Image (4x)** (u)
- **Remove Upscaling** (Shift+U)
- **Scale to Native Size** (s)
- **Scale to Fill Screen** (f)
- **Rotate Clockwise** (r)
- **Rotate Counter-Clockwise** (Shift+R)

### Slideshow Menu
- **Play / Pause Slideshow** (Space) - Toggle auto-advance through images

## Technical Details

### Built With
- **SwiftUI** - Modern declarative UI framework
- **AppKit** - macOS native components
- **Core Image** - Auto-enhancement and noise reduction filters
- **Real-ESRGAN** - AI-powered image upscaling

### Image Processing
- Images are sorted by creation date
- Auto-enhancement uses Core Image's `autoAdjustmentFilters()`
- Image smoothing uses Core Image's `CINoiseReduction` filter
- AI upscaling uses Real-ESRGAN (4x) via bundled `realesrgan-ncnn-vulkan` binary
- Upscaling is applied to the best available version (smoothed > enhanced > original)
- Adding or removing enhance/smooth invalidates any existing upscale
- All edits are session-persistent; original images are never modified on disk

### Architecture
- `SlideyApp.swift` - Main app entry point and menu commands
- `SlideshowView.swift` - Main slideshow interface and controls
- `ImageLoader.swift` - Directory scanning and image loading
- `RecentDirectories.swift` - Recent directory management
- `Resources/realesrgan-ncnn-vulkan` - Bundled AI upscaling binary
- `Resources/models/` - Real-ESRGAN model files

## Requirements

- macOS 26.0 or later
- Xcode 15.0 or later (for building)

## Building

1. Open `slidey.xcodeproj` in Xcode
2. Select your target device (e.g., "My Mac")
3. Press Command+R to build and run

## Roadmap / TODO

Ideas worth implementing — not yet started.

### Slideshow proper
- [x] Auto-advance with configurable interval + play/pause
- [ ] Prevent display sleep / screensaver while in fullscreen (IOKit power assertion)

### Library ergonomics
- [x] Drag-and-drop a folder onto the window to open it (also dock icon and "Open With…")
- [x] Sort options (name, creation, modification, random) — View → Sort By, with default in Settings
- [ ] Move-to-trash key and "Reveal in Finder" (confirm before trashing)
- [ ] Auto-open most recent directory at launch
- [ ] Image counter (`3 / 47`) alongside the existing filename overlay
- [x] Watch directory for new/removed files without requiring a reopen (`DispatchSource`)

### Image viewing
- [x] Continuous zoom/pan via scroll + pinch, beyond the current binary native/fill modes
- [x] Save / Export edited images — auto-enhance, smooth, rotate, upscale results currently live only in memory
- [x] Cancel button + progress indicator for AI upscale (4x can be slow with no way to bail)
- [x] Thumbnail strip / jump-to-index for large folders

## License

Created for personal use.
