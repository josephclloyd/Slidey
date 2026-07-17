# Slidey

A native macOS slideshow application for viewing and editing images, with a deep
set of AI-powered enhancement tools, per-image session editing, and display
controls — all driven by fast single-key shortcuts.

## Features

### Viewing & navigation
- **Directory-based slideshow** — select any folder and browse every image in it
- **Fullscreen mode** — automatic fullscreen on launch; toggle with `⌃⌘F`
- **Auto-advance slideshow** — play / pause with Space; interval, loop, and shuffle configurable in Settings
- **Crossfade transitions** — optional smooth crossfade between images, with configurable duration
- **Zoom & pan** — scale to native size or fill screen, smart zoom, and arrow-key panning of zoomed images
- **Thumbnail strip** — toggleable filmstrip with an LRU thumbnail cache
- **Recent directories** — quick access to recently opened folders, reopened across launches via security-scoped bookmarks
- **Multiple windows** — open several slideshows at once; optionally float a window above others
- **Filename & EXIF overlays** — toggle the filename or a detailed metadata overlay (dimensions, file size, date taken, camera)
- **Favourites & star ratings** — mark favourites, set 1–5 star ratings, and filter the slideshow by them
- **Background music** — Apple Music integration via MusicKit (single song, playlist, or shuffle library)

### Enhancement & AI editing
All edits are session-persistent and keyed per image — original files are never modified on disk unless you explicitly save or export.

- **Auto-enhance** — one-key Core Image enhancement
- **Smooth / sharpen** — noise reduction and sharpening filters
- **AI upscaling** — 2× and 4× upscaling via bundled Real-ESRGAN
- **Denoise** — adjustable Core Image noise reduction (HUD)
- **JPEG cleanup** — adjustable SwinIR compression-artifact removal (HUD), plus a one-shot artifact-removal pass
- **AI grain reduction** — adjustable Restormer real sensor/ISO noise removal (HUD)
- **Adjustments & curves** — brightness/contrast/saturation HUD and a curves / color-grading HUD
- **Vignette** — adjustable vignette HUD
- **Local adjustments** — brush-based dodge/burn
- **Photo effects** — Mono, Noir, Fade, Chrome, Process, Tonal
- **Before/after preview** — hold `b` to peek at the original

### Retouch & repair
- **Face restoration** — AI face restoration via CodeFormer
- **Red-eye removal** — automatic red-eye correction
- **Background removal** — foreground isolation
- **Colorization** — DDColor B&W-to-color
- **Object removal** — inpainting to erase unwanted objects

### Geometry
- **Rotate & flip** — 90° rotation and horizontal/vertical flip
- **Crop** — interactive crop
- **Straighten** — angle-correction HUD
- **Perspective correction** — four-corner perspective fix

### Workflow
- **Undo** — standard `⌘Z` undo for edits
- **Copy / paste adjustments** — replicate a set of edits from one image to another
- **Batch apply** — apply the current edits to all images or just favourites
- **Save / export** — save edits in place or export a copy; export all visible (filtered) images
- **Share & print** — macOS share sheet and printing
- **File operations** — reveal in Finder, open in Preview / open with, rename, move to Trash, copy/move to another folder, set as desktop picture
- **Clipboard** — copy the current image or its file path

## Keyboard Shortcuts

### Navigation
- **← / Right-click** — Previous image
- **→ / Click** — Next image
- **Home / End** — First / last image
- **j** — Jump to a random image
- **Arrow keys** — Pan the image (when zoomed)

### Display
- **⌘+ / + / =** — Zoom in
- **⌘- / - / _** — Zoom out
- **s** — Scale to native size (1:1)
- **f** — Scale to fill screen
- **z** — Smart zoom
- **r / ⇧R** — Rotate clockwise / counter-clockwise
- **c / ⇧C** — Flip horizontal / vertical
- **n** — Toggle filename overlay
- **i** — Toggle image info (EXIF) overlay
- **/ (or ⌘/)** — Toggle keyboard-shortcuts overlay
- **d** — Toggle debug window
- **⌃⌘F** — Toggle fullscreen
- **Escape** — Exit fullscreen, or cancel an active HUD / crop / upscale

### Enhancement & AI editing
- **a / ⇧A** — Auto-enhance / remove enhancement
- **m / ⇧M** — Smooth / remove smoothing
- **h / ⇧H** — Sharpen / remove sharpening
- **u / ⌥U / ⇧U** — AI upscale 2× / 4× / remove (Real-ESRGAN)
- **q** — Denoise HUD (Core Image, adjustable)
- **⇧Q** — JPEG Cleanup HUD (SwinIR, adjustable)
- **l / ⇧L** — Remove JPEG artifacts (SwinIR) / restore
- **⇧N** — AI Grain Reduction HUD (Restormer, adjustable)
- **e** — Adjustments HUD
- **⇧E** — Curves / color-grading HUD
- **b** (hold) — Preview the original (before/after)

Vignette, Local Adjustments, and Photo Effects are menu-driven (Edit ▸ Tone & Color).

### Retouch
- **p / ⇧P** — Restore faces (CodeFormer) / remove
- **g / ⇧G** — Red-eye removal / remove correction
- **k / ⇧K** — Remove background / restore
- **o / ⇧O** — Colorize (DDColor) / remove
- **⌥O** — Remove object (inpainting)

### Geometry
- **w / ⇧W** — Crop / remove crop
- **y / ⇧Y** — Straighten HUD / remove
- **⌥Y** — Perspective correction

### Favourites & rating
- **x** — Toggle favourite
- **v** — Show favourites only
- **1–5** — Set star rating
- **0** — Clear star rating

### Slideshow
- **Space** — Play / pause auto-advance (interval set in Settings)
- **t** — Toggle thumbnail strip

### File & editing workflow
- **⌘O** — Open directory
- **⇧⌘O** — Open in Preview
- **⌘S** — Save edited image
- **⇧⌘S** — Export with edits…
- **⇧⌘E** — Export visible images…
- **⌘R** — Reveal in Finder
- **⇧⌘R** — Rename image
- **⌘⌫** — Move to Trash
- **⌥⌘C / ⇧⌘M** — Copy / move to another folder
- **⌘C** — Copy image to clipboard
- **⇧⌘C** — Copy file path
- **⌥⌘C / ⌥⌘V** — Copy / paste adjustments
- **⌘P** — Print
- **⌘Z** — Undo last edit

> **Note:** ⌥⌘C is shared between **Copy to Folder** and **Copy Adjustments** — both are bound to the same key, so whichever the system resolves first fires.

### Window
- **⌘N** — New window
- **⌘,** — Settings

## Usage

1. Launch Slidey
2. Press `⌘O` (or use File ▸ Open…) and choose a folder of images
3. Navigate with the arrow keys or clicks
4. Apply enhancements, retouching, or geometry edits with the shortcuts above
5. Save or export when you're happy, or just browse — nothing is written to disk until you ask

## Supported Formats

- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- BMP (.bmp)
- TIFF (.tiff)
- HEIC (.heic)
- WebP (.webp)
- RAW (view/browse only) — Canon (.cr2, .cr3), Nikon (.nef), Sony (.arw), Adobe (.dng), Fujifilm (.raf), Olympus (.orf), Panasonic (.rw2), Pentax (.pef), Samsung (.srw), decoded via ImageIO

## Menu Commands

### File
- **New Window** (`⌘N`), **Open…** (`⌘O`), **Recent Directories**
- **Save Edited Image** (`⌘S`), **Export with Edits…** (`⇧⌘S`)
- **Reveal in Finder** (`⌘R`), **Open in Preview** (`⇧⌘O`), **Open With…**
- **Rename…** (`⇧⌘R`), **Move to Trash** (`⌘⌫`)
- **Copy to Folder…** (`⌥⌘C`), **Move to Folder…** (`⇧⌘M`), **Export Visible Images…** (`⇧⌘E`)
- **Set as Desktop Picture**, **Share…**, **Print…** (`⌘P`)

### Edit
- **Copy Image** (`⌘C`), **Copy File Path** (`⇧⌘C`)
- **Copy / Paste Adjustments** (`⌥⌘C` / `⌥⌘V`) — note ⌥⌘C is shared with **Copy to Folder** above; whichever the system resolves first fires
- **Scale to Native Size** (`s`), **Scale to Fill Screen** (`f`)
- **Enhance** submenu — auto-enhance, smooth, sharpen, AI upscale (2×/4×)
- **Denoise & Cleanup** submenu — denoise, JPEG cleanup, AI grain reduction, remove artifacts
- **Tone & Color** submenu — adjustments, curves, vignette, local adjustments, photo effects
- **Retouch** submenu — restore faces, red-eye, background removal, colorize, object removal
- **Geometry** submenu — rotate, flip, crop, straighten, perspective correction
- **Apply Edits to All Images… / to Favourites…** (batch apply)

### View
- **Enter Full Screen** (`⌃⌘F`), **Zoom In/Out** (`⌘+` / `⌘-`)
- **Smart Zoom** (`z`), **Shortcuts Overlay** (`/`), **Sort By**

### Slideshow
- **Play / Pause Slideshow** (`Space`), **Shuffle on Advance**
- **Toggle Thumbnail Strip** (`t`), **Toggle Image Info** (`i`)
- **Toggle Favourite** (`x`), **Show Favourites Only** (`v`), **Filter by Rating**

### Music
- **Stop Music**, **Play Song…**, **Play Playlist…**, **Shuffle Library**

### Window
- **Float Above Other Windows**

### Help
- **Keyboard Shortcuts** (`⌘/`), **Tools Guide**

## Technical Details

### Built With
- **SwiftUI** + **AppKit** — native macOS UI
- **Core Image** — enhancement, noise reduction, adjustments, curves, vignette, photo effects
- **Vision** — face and feature detection (face restoration, red-eye)
- **Core ML** — SwinIR (JPEG cleanup), Restormer (grain reduction), CodeFormer (face restoration), DDColor (colorization), and inpainting models
- **Real-ESRGAN** — AI image upscaling via the bundled `realesrgan-ncnn-vulkan` binary
- **MusicKit** — background music playback

### Image Processing Notes
- Images are sorted per the Settings sort order (creation date by default)
- Every edit is session-persistent and keyed by image URL, so it survives directory rescans and index shifts
- The single display-commit path keeps photo effects in sync across all edits
- Tiled Core ML inference runs on CPU+GPU with a per-tile cancellation token and a load timeout
- Original images are never modified on disk unless you explicitly save or export

### Architecture
- `SlideyApp.swift` — app entry point, AppDelegate, menu commands, Settings scene
- `SlideshowView.swift` — main slideshow interface, image display, key handling, overlays
- `SlideshowView+*.swift` — feature extensions (AI edits, crop, curves, straighten, vignette, local adjustments, object removal, perspective, grain reduction, undo, batch apply, export, rating, persistence)
- `ImageLoader.swift` — directory scanning, decoding, caching, and file-system watching
- `MusicManager.swift` — background music via MusicKit
- `RecentDirectories.swift` — security-scoped bookmark persistence for recent folders
- `Resources/realesrgan-ncnn-vulkan` + `Resources/models/` — bundled upscaling binary and model files

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later (for building)

## Building

```bash
# From the repo root:
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO

# Run the built app:
open ~/Library/Developer/Xcode/DerivedData/Slidey-*/Build/Products/Debug/Slidey.app
```

Or open `Slidey.xcodeproj` in Xcode and press `⌘R`.

## License

Created for personal use.
