import SwiftUI
import AppKit

@main
struct SlideyApp: App {
    @StateObject private var recentDirectories = RecentDirectories()

    var body: some Scene {
        WindowGroup {
            SlideshowView()
                .environmentObject(recentDirectories)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            FileMenuCommands(recentDirectories: recentDirectories)
            EditMenuCommands()
        }
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
                    ForEach(recentDirectories.directories, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("OpenDirectory"),
                                object: url
                            )
                        }
                    }
                }
            }
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
