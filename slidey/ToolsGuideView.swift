import SwiftUI

struct ToolsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private static let sections: [ToolSection] = [
        ToolSection(title: "Enhance", tools: [
            ToolEntry(
                name: "Auto-Enhance",
                key: "a",
                removeKey: "A",
                summary: "One-click brightness, contrast, and saturation boost using Core Image auto-adjustment filters.",
                when: "Quick improvement for dull or underexposed photos. Non-destructive \u{2014} toggle on/off instantly."
            ),
            ToolEntry(
                name: "Smooth",
                key: "m",
                removeKey: "M",
                summary: "Softens the image with a light Gaussian blur.",
                when: "Reducing visible noise or harshness in a photo at the cost of some detail. For targeted noise reduction, see the Denoise tools below."
            ),
            ToolEntry(
                name: "Sharpen",
                key: "h",
                removeKey: "H",
                summary: "Increases edge contrast using Core Image\u{2019}s unsharp-mask sharpening.",
                when: "Making slightly soft images look crisper. Works well after Smooth or Upscale to restore some edge definition."
            ),
            ToolEntry(
                name: "AI Upscale (2\u{00d7} / 4\u{00d7})",
                key: "u / \u{2325}U",
                removeKey: "U",
                summary: "Doubles or quadruples the image resolution using Real-ESRGAN, an AI super-resolution model.",
                when: "Enlarging small or low-resolution images for printing or closer inspection. Processing time depends on image size."
            ),
        ]),
        ToolSection(title: "Denoise & Cleanup", note: "These three tools target different kinds of image degradation \u{2014} using the wrong one won\u{2019}t help and may soften the image unnecessarily.", tools: [
            ToolEntry(
                name: "Denoise",
                key: "q",
                removeKey: nil,
                summary: "Classical noise reduction using Core Image\u{2019}s CINoiseReduction filter. Opens a HUD with an adjustable strength slider.",
                when: "General-purpose noise reduction. Fast and lightweight, but less effective than AI Grain Reduction on heavy real-camera noise. Good first choice for mild noise.",
                differs: "Unlike JPEG Cleanup and AI Grain Reduction, this uses a traditional (non-AI) algorithm \u{2014} faster but less targeted."
            ),
            ToolEntry(
                name: "JPEG Cleanup",
                key: "Q",
                removeKey: nil,
                summary: "Removes JPEG compression blocking artifacts using a SwinIR neural network. Opens a HUD with adjustable strength.",
                when: "Images saved as low-quality JPEG that show visible blocky artifacts, banding, or ringing around edges. This is specifically for compression damage, not camera sensor noise.",
                differs: "Targets JPEG compression artifacts only (the blocky/banded look from heavy JPEG compression). Will not help with grainy photos from high-ISO shooting \u{2014} use AI Grain Reduction for that."
            ),
            ToolEntry(
                name: "AI Grain Reduction",
                key: "N",
                removeKey: nil,
                summary: "Reduces real sensor/ISO grain using a Restormer neural network. Opens a HUD with adjustable strength that defaults based on detected noise level.",
                when: "Photos shot at high ISO (low light, indoor, night) that show visible grain or speckle. This is the tool for real camera noise.",
                differs: "Targets real sensor noise (grain from high-ISO capture), not JPEG compression artifacts. More powerful than classical Denoise but slower (AI-based). Default strength scales with detected noise level to avoid over-smoothing clean images."
            ),
            ToolEntry(
                name: "Artifact Removal",
                key: "l",
                removeKey: "L",
                summary: "General-purpose artifact removal using a SwinIR model. One-click, no adjustable strength.",
                when: "Miscellaneous image artifacts that don\u{2019}t fall neatly into JPEG blocking or sensor grain categories."
            ),
        ]),
        ToolSection(title: "Tone & Color", tools: [
            ToolEntry(
                name: "Adjustments",
                key: "e",
                removeKey: nil,
                summary: "Opens a HUD for brightness, contrast, saturation, exposure, highlights, shadows, and temperature adjustments.",
                when: "Fine-tuning the look of an image with standard photo-editing controls."
            ),
            ToolEntry(
                name: "Curves",
                key: "E",
                removeKey: nil,
                summary: "Opens a curves HUD for precise tonal control via adjustable control points on an RGB curve.",
                when: "Advanced tonal adjustments \u{2014} more precise control than the Adjustments sliders for shadows, midtones, and highlights."
            ),
            ToolEntry(
                name: "Vignette",
                key: "Menu only",
                removeKey: nil,
                summary: "Opens a HUD to add a darkened-edge vignette effect with adjustable radius and intensity.",
                when: "Drawing the viewer\u{2019}s eye toward the centre of the image."
            ),
            ToolEntry(
                name: "Selective Colour",
                key: "\u{21e7}V",
                removeKey: nil,
                summary: "Opens a HUD to keep one hue vivid while desaturating everything else to greyscale, with adjustable hue centre and range. Remove via Edit \u{203a} Remove Selective Colour.",
                when: "Isolating a single colour for a colour-pop effect against a monochrome background."
            ),
            ToolEntry(
                name: "Local Adjustments",
                key: "Menu only",
                removeKey: nil,
                summary: "Brush-based dodge and burn. Paint over areas to lighten (dodge) or darken (burn) selectively.",
                when: "Adjusting exposure in specific areas without affecting the whole image."
            ),
            ToolEntry(
                name: "Photo Effects",
                key: "Menu only",
                removeKey: nil,
                summary: "Applies a global look (Mono, Noir, Fade, Chrome, Process, Tonal) using Core Image photo-effect filters.",
                when: "Applying a stylistic look to the entire image. These are non-destructive and can be changed or removed at any time."
            ),
        ]),
        ToolSection(title: "Retouch", note: "Each tool in this group targets a specific retouching task \u{2014} they are not interchangeable.", tools: [
            ToolEntry(
                name: "Restore Faces",
                key: "p",
                removeKey: "P",
                summary: "Enhances and restores facial detail using the CodeFormer AI model. Detects faces automatically and improves clarity, sharpness, and feature definition.",
                when: "Old, blurry, or low-resolution photos where faces are degraded. Works best on portraits and group photos with visible faces.",
                differs: "Restores overall facial quality (sharpness, detail, expression). For just fixing red-eye flash artifacts, use Red-Eye Removal instead."
            ),
            ToolEntry(
                name: "Red-Eye Removal",
                key: "g",
                removeKey: "G",
                summary: "Detects and corrects red-eye caused by camera flash using Core Image\u{2019}s CIRedEyeCorrection filter.",
                when: "Photos taken with flash where subjects have visible red-eye.",
                differs: "Only fixes red-eye flash artifacts \u{2014} a very targeted correction. Does not enhance or restore facial detail (use Restore Faces for that)."
            ),
            ToolEntry(
                name: "Remove Background",
                key: "k",
                removeKey: "K",
                summary: "Isolates the foreground subject by removing the background, using Apple\u{2019}s Vision framework person/subject segmentation.",
                when: "Extracting a person or object from their background. The result has a transparent background (shown as a checkerboard pattern)."
            ),
            ToolEntry(
                name: "Colorize",
                key: "o",
                removeKey: "O",
                summary: "Converts a black-and-white or grayscale photo to color using the DDColor AI model.",
                when: "Old black-and-white photographs that you want to see in color. Expects grayscale/B&W input \u{2014} the app will ask for confirmation if the image is already in color, since colorizing a color photo produces unpredictable results.",
                differs: "This is a creative/restoration tool for B&W photos, not a colour-correction tool. For adjusting colours on an already-colour image, use Adjustments or Curves instead."
            ),
            ToolEntry(
                name: "Remove Object",
                key: "\u{2325}O",
                removeKey: nil,
                summary: "Paint over an unwanted object with a brush, then the LaMa inpainting model fills the area to match the surroundings.",
                when: "Removing unwanted objects, blemishes, text overlays, or distractions from a photo. Paint over the area to remove, then confirm."
            ),
        ]),
        ToolSection(title: "Geometry", tools: [
            ToolEntry(
                name: "Rotate",
                key: "r / R",
                removeKey: nil,
                summary: "Rotates the image 90\u{00b0} clockwise or counter-clockwise.",
                when: "Correcting image orientation."
            ),
            ToolEntry(
                name: "Flip",
                key: "c / C",
                removeKey: nil,
                summary: "Mirrors the image horizontally or vertically.",
                when: "Correcting mirrored images (e.g. selfie-mode front camera)."
            ),
            ToolEntry(
                name: "Crop",
                key: "w",
                removeKey: "W",
                summary: "Opens a crop overlay with draggable handles to select a region of the image to keep.",
                when: "Removing unwanted edges or recomposing the image frame."
            ),
            ToolEntry(
                name: "Straighten",
                key: "y",
                removeKey: "Y",
                summary: "Opens a HUD with a rotation slider for fine-angle adjustments to level a tilted horizon or straighten a composition.",
                when: "Photos where the horizon or a key line is slightly tilted."
            ),
            ToolEntry(
                name: "Perspective Correction",
                key: "\u{2325}Y",
                removeKey: nil,
                summary: "Automatically corrects perspective distortion (converging verticals, keystoning) using Core Image.",
                when: "Architectural photos or shots of buildings where vertical lines converge due to camera tilt."
            ),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tools Guide")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Self.sections) { section in
                        toolSection(section)
                    }
                }
                .padding()
            }
        }
        .frame(width: 560, height: 640)
    }

    private func toolSection(_ section: ToolSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .foregroundColor(.secondary)

            if let note = section.note {
                Text(note)
                    .font(.callout)
                    .foregroundColor(.orange)
                    .padding(.bottom, 2)
            }

            ForEach(section.tools) { tool in
                toolCard(tool)
            }
        }
    }

    private func toolCard(_ tool: ToolEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.name)
                    .fontWeight(.semibold)
                Spacer()
                HStack(spacing: 4) {
                    Text(tool.key)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    if let removeKey = tool.removeKey {
                        Text(removeKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }

            Text(tool.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use when: " + tool.when)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let differs = tool.differs {
                Text(differs)
                    .font(.callout)
                    .italic()
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}

private struct ToolSection: Identifiable {
    let id = UUID()
    let title: String
    var note: String? = nil
    let tools: [ToolEntry]
}

private struct ToolEntry: Identifiable {
    let id = UUID()
    let name: String
    let key: String
    var removeKey: String? = nil
    let summary: String
    let when: String
    var differs: String? = nil
}
