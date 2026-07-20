import SwiftUI
import AppKit

struct HasCurrentImageKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var hasCurrentImage: Bool? {
        get { self[HasCurrentImageKey.self] }
        set { self[HasCurrentImageKey.self] = newValue }
    }
}

@main
struct SlideyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recentDirectories = RecentDirectories()

    var body: some Scene {
        WindowGroup {
            SlideshowView()
                .environmentObject(recentDirectories)
                .environmentObject(appDelegate.pendingOpens)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            FileMenuCommands(recentDirectories: recentDirectories)
            EditMenuCommands()
            ViewMenuCommands()
            WindowMenuCommands()
            SlideshowMenuCommands()
            MusicMenuCommands()
            HelpMenuCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct ViewMenuCommands: Commands {
    @AppStorage("sortOrder") private var sortOrder: AppSortOrder = .creationDateAscending

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Enter Full Screen") {
                NotificationCenter.default.post(name: .toggleFullScreen, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.control, .command])

            Divider()

            Button("Zoom In") {
                NotificationCenter.default.post(name: .zoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .zoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Smart Zoom (z)") {
                NotificationCenter.default.post(name: .toggleSmartZoom, object: nil)
            }

            Button("Shortcuts Overlay (/)") {
                NotificationCenter.default.post(name: .toggleShortcutsOverlay, object: nil)
            }

            Divider()
            Picker("Sort By", selection: $sortOrder) {
                ForEach(AppSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
        }
    }
}

struct SlideshowMenuCommands: Commands {
    @AppStorage("shuffleOnAdvance") private var shuffleOnAdvance: Bool = false
    @AppStorage("minimumRatingFilter") private var minimumRatingFilter: Int = 0

    var body: some Commands {
        CommandMenu("Slideshow") {
            // No keyboard shortcuts here — the SlideshowView's .onKeyPress
            // already binds Space and "t" directly because .focusable() takes
            // priority over menu key-equivalents. Labels show the binding for
            // discoverability.
            Button("Play / Pause Slideshow (Space)") {
                NotificationCenter.default.post(name: .toggleSlideshow, object: nil)
            }
            Toggle("Shuffle on Advance", isOn: $shuffleOnAdvance)

            Divider()

            Button("Toggle Thumbnail Strip (t)") {
                NotificationCenter.default.post(name: .toggleThumbnails, object: nil)
            }
            Button("Toggle Image Info (i)") {
                NotificationCenter.default.post(name: .toggleImageInfo, object: nil)
            }

            Divider()

            Button("Toggle Favourite (x)") {
                NotificationCenter.default.post(name: .toggleFavourite, object: nil)
            }
            Button("Show Favourites Only (v)") {
                NotificationCenter.default.post(name: .toggleFavouritesOnly, object: nil)
            }

            Divider()

            Picker("Filter by Rating", selection: $minimumRatingFilter) {
                Text("Off").tag(0)
                Text("\u{2265} \u{2605}").tag(1)
                Text("\u{2265} \u{2605}\u{2605}").tag(2)
                Text("\u{2265} \u{2605}\u{2605}\u{2605}").tag(3)
                Text("\u{2265} \u{2605}\u{2605}\u{2605}\u{2605}").tag(4)
                Text("\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}").tag(5)
            }
        }
    }
}

struct MusicMenuCommands: Commands {
    @AppStorage("musicMode") private var musicMode: String = "off"
    @AppStorage("musicSongTitle") private var songTitle: String = ""
    @AppStorage("musicPlaylistName") private var playlistName: String = ""

    private var statusLabel: String {
        switch musicMode {
        case "song" where !songTitle.isEmpty: return "Now Playing: \(songTitle)"
        case "playlist" where !playlistName.isEmpty: return "Now Playing: \(playlistName)"
        case "random": return "Now Playing: Shuffle"
        default: return "Not Playing"
        }
    }

    var body: some Commands {
        CommandMenu("Music") {
            Text(statusLabel)

            Divider()

            Button("Stop Music") {
                NotificationCenter.default.post(name: .musicOff, object: nil)
            }
            .disabled(musicMode == "off")

            Divider()

            Button("Play Song\u{2026}") {
                NotificationCenter.default.post(name: .musicChooseSong, object: nil)
            }

            Button("Play Playlist\u{2026}") {
                NotificationCenter.default.post(name: .musicChoosePlaylist, object: nil)
            }

            Button("Shuffle Library") {
                NotificationCenter.default.post(name: .musicShuffle, object: nil)
            }
        }
    }
}

/// Receives folder URLs from Launch Services (drag-onto-dock-icon, "Open With\u{2026}",
/// or `open -a Slidey /path/to/folder`) and forwards them to the active
/// SlideshowView via `pendingOpens`. URLs that arrive before any view is on
/// screen (cold-launch) are buffered until the first SlideshowView appears.
class AppDelegate: NSObject, NSApplicationDelegate {
    let pendingOpens = PendingOpens()
    private var frameObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let window = note.object as? NSWindow,
                  window.frameAutosaveName.isEmpty else { return }
            window.setFrameAutosaveName("MainWindow")
            if let obs = self.frameObserver {
                NotificationCenter.default.removeObserver(obs)
                self.frameObserver = nil
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }
            pendingOpens.send(url)
        }
    }
}

class PendingOpens: ObservableObject {
    @Published var pending: URL?

    func send(_ url: URL) {
        DispatchQueue.main.async {
            self.pending = url
        }
    }
}

struct SettingsView: View {
    @AppStorage("naturalScrollPan") private var naturalScrollPan: Bool = false
    @AppStorage("slideshowInterval") private var slideshowInterval: Double = 5
    @AppStorage("slideshowLoop") private var slideshowLoop: Bool = true
    @AppStorage("sortOrder") private var sortOrder: AppSortOrder = .creationDateAscending
    @AppStorage("autoOpenRecent") private var autoOpenRecent: Bool = true
    @AppStorage("autoPlayMusic") private var autoPlayMusic: Bool = true
    @AppStorage("musicMode") private var musicMode: String = "off"
    @AppStorage("lastMusicMode") private var lastMusicMode: String = "off"
    @AppStorage("musicSongTitle") private var musicSongTitle: String = ""
    @AppStorage("musicPlaylistName") private var musicPlaylistName: String = ""
    @AppStorage("transitionsEnabled") private var transitionsEnabled: Bool = false
    @AppStorage("transitionDuration") private var transitionDuration: Double = 0.3

    private var musicSelectionText: String {
        let mode = musicMode != "off" ? musicMode : lastMusicMode
        switch mode {
        case "song" where !musicSongTitle.isEmpty:
            return "Selection: \(musicSongTitle)\(musicMode == "off" ? " (stopped)" : "")"
        case "playlist" where !musicPlaylistName.isEmpty:
            return "Selection: \(musicPlaylistName)\(musicMode == "off" ? " (stopped)" : "")"
        case "random":
            return "Selection: Shuffle Library\(musicMode == "off" ? " (stopped)" : "")"
        default:
            return "No music selected. Use the Music menu to choose a song or playlist."
        }
    }

    var body: some View {
        Form {
            Section("Library") {
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(AppSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
            }
            Section("Startup") {
                Toggle("Reopen last directory on launch", isOn: $autoOpenRecent)
            }
            Section("Slideshow") {
                Toggle("Loop slideshow", isOn: $slideshowLoop)
                Stepper(value: $slideshowInterval, in: 1...60, step: 1) {
                    Text("Interval: \(Int(slideshowInterval)) second\(Int(slideshowInterval) == 1 ? "" : "s")")
                }
            }
            Section("Transitions") {
                Toggle("Crossfade between images", isOn: $transitionsEnabled)
                if transitionsEnabled {
                    Stepper(value: $transitionDuration, in: 0.1...2.0, step: 0.1) {
                        Text("Duration: \(String(format: "%.1f", transitionDuration))s")
                    }
                }
            }
            Section(
                header: Text("Music"),
                footer: Text(musicSelectionText)
            ) {
                Toggle("Resume music when starting slideshow", isOn: $autoPlayMusic)
            }
            Section(
                header: Text("Input"),
                footer: Text("When on, the image follows your fingers (macOS-native feel). When off, scroll direction is inverted.")
            ) {
                Toggle("Natural scroll pan", isOn: $naturalScrollPan)
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: transitionsEnabled)
        .frame(width: 420)
    }
}

struct FileMenuCommands: Commands {
    @ObservedObject var recentDirectories: RecentDirectories
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.hasCurrentImage) private var hasCurrentImage

    private var imageLoaded: Bool { hasCurrentImage ?? false }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open...") {
                openDirectory()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Menu("Recent Directories") {
                if recentDirectories.directories.isEmpty {
                    Text("No Recent Directories")
                        .disabled(true)
                } else {
                    ForEach(recentDirectories.directories) { entry in
                        Button(entry.displayName) {
                            NotificationCenter.default.post(
                                name: .openDirectory,
                                object: entry
                            )
                        }
                    }
                }
            }

            Divider()

            Button("Save Edited Image") {
                NotificationCenter.default.post(name: .saveEditedImage, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!imageLoaded)

            Button("Export with Edits\u{2026}") {
                NotificationCenter.default.post(name: .exportWithEdits, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!imageLoaded)

            Divider()

            Button("Reveal in Finder") {
                NotificationCenter.default.post(name: .revealInFinder, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!imageLoaded)

            Button("Open in Preview") {
                NotificationCenter.default.post(name: .openInPreview, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!imageLoaded)

            Button("Open With\u{2026}") {
                NotificationCenter.default.post(name: .openWith, object: nil)
            }
            .disabled(!imageLoaded)

            Button("Rename\u{2026}") {
                NotificationCenter.default.post(name: .renameImage, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!imageLoaded)

            Button("Edit Metadata\u{2026}") {
                NotificationCenter.default.post(name: .editMetadata, object: nil)
            }
            .disabled(!imageLoaded)

            Button("Move to Trash") {
                NotificationCenter.default.post(name: .moveToTrash, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!imageLoaded)

            Divider()

            Button("Copy to Folder\u{2026}") {
                NotificationCenter.default.post(name: .copyToFolder, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!imageLoaded)

            Button("Move to Folder\u{2026}") {
                NotificationCenter.default.post(name: .moveToFolder, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!imageLoaded)

            Button("Export Visible Images\u{2026}") {
                NotificationCenter.default.post(name: .exportVisibleImages, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!imageLoaded)

            Divider()

            Button("Set as Desktop Picture") {
                NotificationCenter.default.post(name: .setDesktopPicture, object: nil)
            }
            .disabled(!imageLoaded)

            Button("Share\u{2026}") {
                NotificationCenter.default.post(name: .shareImage, object: nil)
            }
            .disabled(!imageLoaded)

            Divider()

            Button("Print\u{2026}") {
                NotificationCenter.default.post(name: .printImage, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!imageLoaded)
        }
    }

    private func openDirectory() {
        NotificationCenter.default.post(name: .selectDirectory, object: nil)
    }
}

struct WindowMenuCommands: Commands {
    @AppStorage("floatAboveOtherWindows") private var floatAboveOtherWindows: Bool = false

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Toggle("Float Above Other Windows", isOn: $floatAboveOtherWindows)
        }
    }
}

struct HelpMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
            }
            .keyboardShortcut("/", modifiers: .command)

            Button("Tools Guide") {
                NotificationCenter.default.post(name: .showToolsGuide, object: nil)
            }
        }
    }
}

struct EditMenuCommands: Commands {
    @AppStorage("activePhotoEffect") private var activePhotoEffect: String = ""

    private var activeEffectLabel: String {
        switch activePhotoEffect {
        case "CIPhotoEffectMono": return "Effect: Mono (B&W)"
        case "CIPhotoEffectNoir": return "Effect: Noir"
        case "CIPhotoEffectFade": return "Effect: Fade (Vintage)"
        case "CIPhotoEffectChrome": return "Effect: Chrome"
        case "CIPhotoEffectProcess": return "Effect: Process"
        case "CIPhotoEffectTonal": return "Effect: Tonal"
        default: return "Effect: None"
        }
    }

    private func postEffect(_ name: String?) {
        NotificationCenter.default.post(name: .applyPhotoEffect, object: name)
    }

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Image") {
                NotificationCenter.default.post(name: .copyImage, object: nil)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Copy File Path") {
                NotificationCenter.default.post(name: .copyFilePath, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Copy Adjustments") {
                NotificationCenter.default.post(name: .copyAdjustments, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Paste Adjustments") {
                NotificationCenter.default.post(name: .pasteAdjustments, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Scale to Native Size") {
                NotificationCenter.default.post(name: .scaleToNative, object: nil)
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Scale to Fill Screen") {
                NotificationCenter.default.post(name: .scaleToFill, object: nil)
            }
            .keyboardShortcut("f", modifiers: [])

            Divider()

            Menu("Enhance") {
                Button("Auto-Enhance Image") {
                    NotificationCenter.default.post(name: .enhanceImage, object: nil)
                }
                .keyboardShortcut("a", modifiers: [])

                Button("Remove Enhancement") {
                    NotificationCenter.default.post(name: .removeEnhancement, object: nil)
                }
                .keyboardShortcut("a", modifiers: .shift)

                Divider()

                Button("Smooth Image") {
                    NotificationCenter.default.post(name: .smoothImage, object: nil)
                }
                .keyboardShortcut("m", modifiers: [])

                Button("Remove Smoothing") {
                    NotificationCenter.default.post(name: .removeSmoothing, object: nil)
                }
                .keyboardShortcut("m", modifiers: .shift)

                Divider()

                Button("Sharpen Image") {
                    NotificationCenter.default.post(name: .sharpenImage, object: nil)
                }
                .keyboardShortcut("h", modifiers: [])

                Button("Remove Sharpening") {
                    NotificationCenter.default.post(name: .removeSharpening, object: nil)
                }
                .keyboardShortcut("h", modifiers: .shift)

                Divider()

                Button("AI Upscale Image (2x)") {
                    NotificationCenter.default.post(name: .upscaleImage2x, object: nil)
                }
                .keyboardShortcut("u", modifiers: [])

                Button("AI Upscale Image (4x)") {
                    NotificationCenter.default.post(name: .upscaleImage4x, object: nil)
                }
                .keyboardShortcut("u", modifiers: .option)

                Button("Remove Upscaling") {
                    NotificationCenter.default.post(name: .removeUpscaling, object: nil)
                }
                .keyboardShortcut("u", modifiers: .shift)
            }

            Menu("Denoise & Cleanup") {
                Button("Denoise\u{2026}") {
                    NotificationCenter.default.post(name: .denoiseImage, object: nil)
                }
                .keyboardShortcut("q", modifiers: [])

                Divider()

                Button("JPEG Cleanup\u{2026}") {
                    NotificationCenter.default.post(name: .jpegCleanupImage, object: nil)
                }
                .keyboardShortcut("q", modifiers: .shift)

                Button("Remove JPEG Cleanup") {
                    NotificationCenter.default.post(name: .removeJPEGCleanup, object: nil)
                }

                Divider()

                Button("AI Grain Reduction\u{2026}") {
                    NotificationCenter.default.post(name: .grainReductionImage, object: nil)
                }
                .keyboardShortcut("n", modifiers: .shift)

                Button("Remove AI Grain Reduction") {
                    NotificationCenter.default.post(name: .removeGrainReduction, object: nil)
                }

                Divider()

                Button("Remove Artifacts") {
                    NotificationCenter.default.post(name: .removeArtifacts, object: nil)
                }
                .keyboardShortcut("l", modifiers: [])

                Button("Restore Artifacts") {
                    NotificationCenter.default.post(name: .restoreArtifacts, object: nil)
                }
                .keyboardShortcut("l", modifiers: .shift)
            }

            Menu("Tone & Color") {
                Button("Adjustments\u{2026}") {
                    NotificationCenter.default.post(name: .adjustmentsImage, object: nil)
                }

                Button("Curves\u{2026}") {
                    NotificationCenter.default.post(name: .curvesImage, object: nil)
                }

                Button("Vignette\u{2026}") {
                    NotificationCenter.default.post(name: .vignetteImage, object: nil)
                }

                Divider()

                Button("Local Adjustments\u{2026}") {
                    NotificationCenter.default.post(name: .localAdjustmentsImage, object: nil)
                }

                Button("Remove Local Adjustments") {
                    NotificationCenter.default.post(name: .removeLocalAdjustments, object: nil)
                }

                Divider()

                Menu("Photo Effect") {
                    Text(activeEffectLabel)
                    Divider()
                    Button("None") { postEffect(nil) }
                    Divider()
                    Button("Mono (B&W)") { postEffect("CIPhotoEffectMono") }
                    Button("Noir (High-contrast B&W)") { postEffect("CIPhotoEffectNoir") }
                    Button("Fade (Vintage)") { postEffect("CIPhotoEffectFade") }
                    Button("Chrome (Vivid)") { postEffect("CIPhotoEffectChrome") }
                    Button("Process (Cool Fade)") { postEffect("CIPhotoEffectProcess") }
                    Button("Tonal (Soft B&W)") { postEffect("CIPhotoEffectTonal") }
                }
            }

            Menu("Retouch") {
                Button("Restore Faces") {
                    NotificationCenter.default.post(name: .restoreFaces, object: nil)
                }
                .keyboardShortcut("p", modifiers: [])

                Button("Remove Face Restoration") {
                    NotificationCenter.default.post(name: .removeFaceRestoration, object: nil)
                }
                .keyboardShortcut("p", modifiers: .shift)

                Divider()

                Button("Remove Red Eye") {
                    NotificationCenter.default.post(name: .redEyeRemoval, object: nil)
                }
                .keyboardShortcut("g", modifiers: [])

                Button("Remove Red-Eye Correction") {
                    NotificationCenter.default.post(name: .removeRedEye, object: nil)
                }
                .keyboardShortcut("g", modifiers: .shift)

                Divider()

                Button("Remove Background") {
                    NotificationCenter.default.post(name: .removeBackground, object: nil)
                }
                .keyboardShortcut("k", modifiers: [])

                Button("Restore Background") {
                    NotificationCenter.default.post(name: .restoreBackground, object: nil)
                }
                .keyboardShortcut("k", modifiers: .shift)

                Divider()

                Button("Colorize (B&W to Color)") {
                    NotificationCenter.default.post(name: .colorizeImage, object: nil)
                }
                .keyboardShortcut("o", modifiers: [])

                Button("Remove Colorization") {
                    NotificationCenter.default.post(name: .removeColorization, object: nil)
                }
                .keyboardShortcut("o", modifiers: .shift)

                Divider()

                Button("Remove Object\u{2026}") {
                    NotificationCenter.default.post(name: .objectRemovalImage, object: nil)
                }
                .keyboardShortcut("o", modifiers: .option)

                Button("Undo Object Removal") {
                    NotificationCenter.default.post(name: .removeObjectRemoval, object: nil)
                }
            }

            Menu("Geometry") {
                Button("Rotate Clockwise") {
                    NotificationCenter.default.post(name: .rotateClockwise, object: nil)
                }
                .keyboardShortcut("r", modifiers: [])

                Button("Rotate Counter-Clockwise") {
                    NotificationCenter.default.post(name: .rotateCounterClockwise, object: nil)
                }
                .keyboardShortcut("r", modifiers: .shift)

                Divider()

                Button("Flip Horizontal") {
                    NotificationCenter.default.post(name: .flipHorizontal, object: nil)
                }
                Button("Flip Vertical") {
                    NotificationCenter.default.post(name: .flipVertical, object: nil)
                }

                Divider()

                Button("Crop\u{2026}") {
                    NotificationCenter.default.post(name: .cropImage, object: nil)
                }
                Button("Remove Crop") {
                    NotificationCenter.default.post(name: .removeCrop, object: nil)
                }

                Divider()

                Button("Straighten\u{2026}") {
                    NotificationCenter.default.post(name: .straightenImage, object: nil)
                }
                .keyboardShortcut("y", modifiers: [])
                Button("Remove Straighten") {
                    NotificationCenter.default.post(name: .removeStraighten, object: nil)
                }
                .keyboardShortcut("y", modifiers: .shift)

                Divider()

                Button("Perspective Correction\u{2026}") {
                    NotificationCenter.default.post(name: .perspectiveCorrection, object: nil)
                }
                .keyboardShortcut("y", modifiers: .option)

                Button("Remove Perspective Correction") {
                    NotificationCenter.default.post(name: .removePerspectiveCorrection, object: nil)
                }
            }

            Divider()

            Button("Apply Edits to All Images\u{2026}") {
                NotificationCenter.default.post(name: .batchApplyAll, object: nil)
            }

            Button("Apply Edits to Favourites\u{2026}") {
                NotificationCenter.default.post(name: .batchApplyFavourites, object: nil)
            }

        }
    }
}
