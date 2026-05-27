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
                NotificationCenter.default.post(name: NSNotification.Name("ToggleSlideshow"), object: nil)
            }
            Button("Toggle Thumbnail Strip (t)") {
                NotificationCenter.default.post(name: NSNotification.Name("ToggleThumbnails"), object: nil)
            }
        }
    }
}

/// Receives folder URLs from Launch Services (drag-onto-dock-icon, "Open With…",
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
                                name: NSNotification.Name("OpenDirectory"),
                                object: entry
                            )
                        }
                    }
                }
            }

            Divider()

            Button("Save Edited Image") {
                NotificationCenter.default.post(name: NSNotification.Name("SaveEditedImage"), object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Divider()

            Button("Reveal in Finder") {
                NotificationCenter.default.post(name: NSNotification.Name("RevealInFinder"), object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Move to Trash") {
                NotificationCenter.default.post(name: NSNotification.Name("MoveToTrash"), object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private func openDirectory() {
        NotificationCenter.default.post(name: NSNotification.Name("SelectDirectory"), object: nil)
    }
}

struct EditMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Auto-Enhance Image") {
                NotificationCenter.default.post(name: NSNotification.Name("EnhanceImage"), object: nil)
            }
            .keyboardShortcut("a", modifiers: [])

            Button("Remove Enhancement") {
                NotificationCenter.default.post(name: NSNotification.Name("RemoveEnhancement"), object: nil)
            }
            .keyboardShortcut("a", modifiers: .shift)

            Divider()

            Button("Smooth Image") {
                NotificationCenter.default.post(name: NSNotification.Name("SmoothImage"), object: nil)
            }
            .keyboardShortcut("m", modifiers: [])

            Button("Remove Smoothing") {
                NotificationCenter.default.post(name: NSNotification.Name("RemoveSmoothing"), object: nil)
            }
            .keyboardShortcut("m", modifiers: .shift)

            Divider()

            Button("AI Upscale Image (4x)") {
                NotificationCenter.default.post(name: NSNotification.Name("UpscaleImage"), object: nil)
            }
            .keyboardShortcut("u", modifiers: [])

            Button("Remove Upscaling") {
                NotificationCenter.default.post(name: NSNotification.Name("RemoveUpscaling"), object: nil)
            }
            .keyboardShortcut("u", modifiers: .shift)

            Divider()

            Button("Scale to Native Size") {
                NotificationCenter.default.post(name: NSNotification.Name("ScaleToNative"), object: nil)
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Scale to Fill Screen") {
                NotificationCenter.default.post(name: NSNotification.Name("ScaleToFill"), object: nil)
            }
            .keyboardShortcut("f", modifiers: [])

            Divider()

            Button("Rotate Clockwise") {
                NotificationCenter.default.post(name: NSNotification.Name("RotateClockwise"), object: nil)
            }
            .keyboardShortcut("r", modifiers: [])

            Button("Rotate Counter-Clockwise") {
                NotificationCenter.default.post(name: NSNotification.Name("RotateCounterClockwise"), object: nil)
            }
            .keyboardShortcut("r", modifiers: .shift)

        }
    }
}
