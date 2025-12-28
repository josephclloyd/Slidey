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
- **Session memory** - Remembers rotations, enhancements, and smoothing per session

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

### Window
- **Escape** - Toggle fullscreen
- **Command+N** - New window
- **Command+O** - Open directory

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
- **Scale to Native Size** (s)
- **Scale to Fill Screen** (f)
- **Rotate Clockwise** (r)
- **Rotate Counter-Clockwise** (Shift+R)

## Technical Details

### Built With
- **SwiftUI** - Modern declarative UI framework
- **AppKit** - macOS native components
- **Core Image** - Auto-enhancement filters

### Image Processing
- Images are sorted by creation date
- Auto-enhancement uses Core Image's `autoAdjustmentFilters()`
- Image smoothing uses Core Image's `CINoiseReduction` filter
- Enhancements, smoothing, and rotations are session-persistent
- Original images are never modified on disk

### Architecture
- `SlideyApp.swift` - Main app entry point and menu commands
- `SlideshowView.swift` - Main slideshow interface and controls
- `ImageLoader.swift` - Directory scanning and image loading
- `RecentDirectories.swift` - Recent directory management

## Requirements

- macOS 26.0 or later
- Xcode 15.0 or later (for building)

## Building

1. Open `slidey.xcodeproj` in Xcode
2. Select your target device (e.g., "My Mac")
3. Press Command+R to build and run

## License

Created for personal use.
