import SwiftUI
import AppKit

extension SlideshowView {
    /// Enters (or exits) the before/after reveal slider: a single fitted image
    /// with a draggable vertical divider showing the pre-edit original on the
    /// left and the current edited result on the right. Complements the `b`
    /// hold-to-preview toggle. Requires the current image to have edits.
    func toggleBeforeAfterSlider() {
        if showBeforeAfterSlider {
            exitBeforeAfterSlider()
            return
        }
        guard imageLoader.currentImage != nil else {
            showErrorToast("No image to compare")
            return
        }
        guard let url = imageLoader.currentImageURL,
              !(editStacks[url]?.isEmpty ?? true) else {
            showErrorToast("No edits to compare on this image")
            return
        }
        beforeAfterSliderPosition = 0.5
        zoomPan.reset()
        slideshow.stop()
        showCompareMode = false
        showBeforeAfterSlider = true
    }

    func exitBeforeAfterSlider() {
        showBeforeAfterSlider = false
    }

    /// Handles key presses while the before/after slider is active. Returns nil
    /// when the slider is not showing (caller continues normal handling). While
    /// active, only Escape or ⇧B exit; all other keys are swallowed so
    /// navigation/edits don't fire behind the reveal.
    func handleBeforeAfterSliderKeyPress(_ keyPress: KeyPress) -> KeyPress.Result? {
        guard showBeforeAfterSlider else { return nil }
        if keyPress.key == .escape || keyPress.characters == "B" {
            exitBeforeAfterSlider()
            return .handled
        }
        return .ignored
    }

    @ViewBuilder var beforeAfterSliderContent: some View {
        BeforeAfterSliderView(
            original: imageLoader.currentImage,
            edited: effectiveDisplayImage,
            rotation: rotationAngle,
            position: $beforeAfterSliderPosition
        )
    }
}

/// Overlays the original (pre-edit) image over the edited image and reveals the
/// original only to the left of a draggable divider. Both images are fitted
/// identically into the container, so the split lines up pixel-for-pixel.
struct BeforeAfterSliderView: View {
    let original: NSImage?
    let edited: NSImage?
    let rotation: Angle
    @Binding var position: CGFloat

    private var clampedPosition: CGFloat { min(1, max(0, position)) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let original, let edited {
                    fittedImage(edited, in: geo.size)
                    fittedImage(original, in: geo.size)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: geo.size.width * clampedPosition)
                                Color.clear
                            }
                        )
                    divider(in: geo.size)
                    labels(in: geo.size)
                } else {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        position = min(1, max(0, value.location.x / geo.size.width))
                    }
            )
        }
    }

    private func fittedImage(_ image: NSImage, in size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotationEffect(rotation)
            .frame(width: size.width, height: size.height)
    }

    private func divider(in size: CGSize) -> some View {
        let x = size.width * clampedPosition
        return ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .position(x: x, y: size.height / 2)
            Circle()
                .fill(Color.white)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                )
                .shadow(radius: 3)
                .position(x: x, y: size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func labels(in size: CGSize) -> some View {
        VStack {
            HStack {
                labelChip("Before")
                Spacer()
                labelChip("After")
            }
            Spacer()
        }
        .padding(20)
        .allowsHitTesting(false)
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.7))
            .cornerRadius(6)
    }
}
