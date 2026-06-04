import SwiftUI
import AppKit

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
            SlideshowMenuCommands()
            MusicMenuCommands()
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
    var body: some Commands {
        CommandMenu("Slideshow") {
            // No keyboard shortcuts here — the SlideshowView's .onKeyPress
            // already binds Space and "t" directly because .focusable() takes
            // priority over menu key-equivalents. Labels show the binding for
            // discoverability.
            Button("Play / Pause Slideshow (Space)") {
                NotificationCenter.default.post(name: .toggleSlideshow, object: nil)
            }
            Button("Toggle Thumbnail Strip (t)") {
                NotificationCenter.default.post(name: .toggleThumbnails, object: nil)
            }
            Button("Toggle Image Info (i)") {
                NotificationCenter.default.post(name: .toggleImageInfo, object: nil)
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
            Section("Music") {
                Toggle("Resume music when starting slideshow", isOn: $autoPlayMusic)
                Text(musicSelectionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Input") {
                Toggle("Natural scroll pan", isOn: $naturalScrollPan)
                Text("When on, the image follows your fingers (macOS-native feel). When off, scroll direction is inverted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct FileMenuCommands: Commands {
    @ObservedObject var recentDirectories: RecentDirectories
    @Environment(\.openWindow) private var openWindow

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

            Divider()

            Button("Reveal in Finder") {
                NotificationCenter.default.post(name: .revealInFinder, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Move to Trash") {
                NotificationCenter.default.post(name: .moveToTrash, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private func openDirectory() {
        NotificationCenter.default.post(name: .selectDirectory, object: nil)
    }
}

struct EditMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Image") {
                NotificationCenter.default.post(name: .copyImage, object: nil)
            }
            .keyboardShortcut("c", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

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

            Button("AI Upscale Image (4x)") {
                NotificationCenter.default.post(name: .upscaleImage, object: nil)
            }
            .keyboardShortcut("u", modifiers: [])

            Button("Remove Upscaling") {
                NotificationCenter.default.post(name: .removeUpscaling, object: nil)
            }
            .keyboardShortcut("u", modifiers: .shift)

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

            Button("Rotate Clockwise") {
                NotificationCenter.default.post(name: .rotateClockwise, object: nil)
            }
            .keyboardShortcut("r", modifiers: [])

            Button("Rotate Counter-Clockwise") {
                NotificationCenter.default.post(name: .rotateCounterClockwise, object: nil)
            }
            .keyboardShortcut("r", modifiers: .shift)

        }
    }
}
