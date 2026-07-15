import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private static let sections: [(String, [(String, String)])] = [
        ("Navigation", [
            ("← / Right-click", "Previous image"),
            ("→ / Click", "Next image"),
            ("Home", "First image"),
            ("End", "Last image"),
            ("j", "Jump to random image"),
            ("↑ ↓ ← →", "Pan (when zoomed)"),
        ]),
        ("Display", [
            ("⌘+ / + / =", "Zoom in"),
            ("⌘- / - / _", "Zoom out"),
            ("s", "Scale to native size (1:1)"),
            ("f", "Scale to fill screen"),
            ("r", "Rotate clockwise"),
            ("⇧R", "Rotate counter-clockwise"),
            ("c", "Flip horizontal (toggle)"),
            ("⇧C", "Flip vertical (toggle)"),
            ("n", "Toggle filename overlay"),
            ("i", "Toggle image info overlay"),
            ("/", "Toggle shortcuts overlay"),
            ("d", "Toggle debug window"),
        ]),
        ("Enhancement", [
            ("a", "Auto-enhance image"),
            ("⇧A", "Remove enhancement"),
            ("m", "Smooth image"),
            ("⇧M", "Remove smoothing"),
            ("u", "AI upscale (2\u{00d7})"),
            ("⌥U", "AI upscale (4\u{00d7})"),
            ("⇧U", "Remove upscaling"),
            ("b (hold)", "Preview original (before/after)"),
            ("Edit > Vignette\u{2026}", "Open Vignette HUD"),
            ("y", "Open Straighten HUD"),
            ("\u{21e7}Y", "Remove straighten"),
            ("\u{2325}Y", "Perspective correction"),
            ("e", "Open Adjustments HUD"),
            ("\u{21e7}E", "Open Curves HUD"),
            ("Edit > Local Adj\u{2026}", "Brush-based dodge/burn"),
            ("p", "Restore faces via AI (CodeFormer)"),
            ("\u{21e7}P", "Remove face restoration"),
            ("g", "Remove red eye"),
            ("\u{21e7}G", "Remove red-eye correction"),
            ("k", "Remove background (foreground isolation)"),
            ("\u{21e7}K", "Restore background"),
            ("l", "Remove JPEG artifacts (SwinIR)"),
            ("\u{21e7}L", "Restore artifacts"),
            ("\u{21e7}Q", "JPEG Cleanup (SwinIR, adjustable)"),
            ("\u{21e7}N", "AI Grain Reduction (Restormer, adjustable)"),
            ("o", "Colorize B&W photo (DDColor)"),
            ("\u{21e7}O", "Remove colorization"),
        ]),
        ("Favourites & Rating", [
            ("x", "Toggle favourite"),
            ("v", "Show favourites only"),
            ("1\u{2013}5", "Set star rating"),
            ("0", "Clear star rating"),
        ]),
        ("Slideshow", [
            ("Space", "Play / pause slideshow"),
            ("t", "Toggle thumbnail strip"),
            ("⌃⌘F", "Toggle fullscreen"),
            ("Escape", "Exit fullscreen / cancel"),
        ]),
        ("File", [
            ("⌘O", "Open directory"),
            ("⌘S", "Save edited image"),
            ("⌘C", "Copy image to clipboard"),
            ("⇧⌘C", "Copy file path to clipboard"),
            ("⌘R", "Reveal in Finder"),
            ("⇧⌘R", "Rename image"),
            ("⌘⌫", "Move to Trash"),
        ]),
        ("Window", [
            ("⌘,", "Settings"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Self.sections, id: \.0) { section in
                        shortcutGroup(section.0, shortcuts: section.1)
                    }
                }
                .padding()
            }
        }
        .frame(width: 420, height: 560)
    }

    private func shortcutGroup(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            ForEach(shortcuts, id: \.0) { key, label in
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .trailing)
                    Text(label)
                    Spacer()
                }
            }
        }
    }
}
