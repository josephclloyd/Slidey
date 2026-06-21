import SwiftUI
import AppKit

enum PanDirection {
    case left, right, up, down
}

func rotatedBoundingBox(_ size: CGSize, by angle: Angle) -> CGSize {
    let c = abs(cos(angle.radians))
    let s = abs(sin(angle.radians))
    return CGSize(
        width: size.width * c + size.height * s,
        height: size.width * s + size.height * c
    )
}

@Observable
final class ZoomPanController {
    var zoomScale: CGFloat = 1.0
    var imageOffset: CGSize = .zero
    var windowSize: CGSize = .zero

    func reset() {
        zoomScale = 1.0
        imageOffset = .zero
    }

    func canPan(direction: PanDirection, image: NSImage?, rotationAngle: Angle) -> Bool {
        guard zoomScale > 1.0,
              let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let natural = CGSize(width: cgImage.width, height: cgImage.height)
        let bb = rotatedBoundingBox(natural, by: rotationAngle)
        let fitScale = min(windowSize.width / bb.width, windowSize.height / bb.height)
        let displayedSize = CGSize(
            width: bb.width * fitScale * zoomScale,
            height: bb.height * fitScale * zoomScale
        )

        let maxOffsetX = max(0, (displayedSize.width - windowSize.width) / 2)
        let maxOffsetY = max(0, (displayedSize.height - windowSize.height) / 2)

        switch direction {
        case .left:
            return imageOffset.width < maxOffsetX - 10
        case .right:
            return imageOffset.width > -maxOffsetX + 10
        case .up:
            return imageOffset.height < maxOffsetY - 10
        case .down:
            return imageOffset.height > -maxOffsetY + 10
        }
    }

    func zoomToNativeSize(image: NSImage?, rotationAngle: Angle) {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let natural = CGSize(width: cgImage.width, height: cgImage.height)
        let bb = rotatedBoundingBox(natural, by: rotationAngle)
        let fitScale = min(windowSize.width / bb.width, windowSize.height / bb.height)
        zoomScale = 1.0 / fitScale
        imageOffset = .zero
    }

    func zoomToFillScreen(image: NSImage?, rotationAngle: Angle) {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let natural = CGSize(width: cgImage.width, height: cgImage.height)
        let bb = rotatedBoundingBox(natural, by: rotationAngle)
        let isPortrait = bb.height > bb.width
        let fitScale = min(windowSize.width / bb.width, windowSize.height / bb.height)
        let fillScale: CGFloat = isPortrait
            ? windowSize.height / bb.height
            : windowSize.width / bb.width

        zoomScale = fillScale / fitScale
        imageOffset = .zero
    }
}

// MARK: - ClickCatcher

struct ClickCatcher: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onZoom: (CGFloat) -> Void
    let onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onZoom = onZoom
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onZoom = onZoom
        nsView.onScroll = onScroll
    }
}

class ClickCatcherView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1.0 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onZoom?(1.0 + event.scrollingDeltaY * 0.005)
        } else {
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - ImageDisplayView

struct ImageDisplayView: View {
    let image: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var imageOffset: CGSize
    let containerSize: CGSize
    @Binding var rotationAngle: Angle
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    @AppStorage("naturalScrollPan") private var naturalScrollPan: Bool = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                let fitted = fittedNaturalSize()
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .rotationEffect(rotationAngle)
                    .scaleEffect(zoomScale)
                    .offset(imageOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ClickCatcher(
                    onLeftClick: onLeftClick,
                    onRightClick: onRightClick,
                    onZoom: { applyZoom($0) },
                    onScroll: { applyPan(dx: $0, dy: $1) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fittedNaturalSize() -> CGSize {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .zero
        }
        let natural = CGSize(width: cg.width, height: cg.height)
        let bb = rotatedBoundingBox(natural, by: rotationAngle)
        guard bb.width > 0, bb.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let fitScale = min(containerSize.width / bb.width, containerSize.height / bb.height)
        return CGSize(width: natural.width * fitScale, height: natural.height * fitScale)
    }

    private func applyZoom(_ factor: CGFloat) {
        let oldScale = zoomScale
        let newScale = max(0.1, min(10.0, oldScale * factor))
        if newScale == oldScale { return }
        let actual = newScale / oldScale
        zoomScale = newScale
        imageOffset = CGSize(
            width: imageOffset.width * actual,
            height: imageOffset.height * actual
        )
        clampOffset()
    }

    private func applyPan(dx: CGFloat, dy: CGFloat) {
        let bounds = panBounds()
        guard bounds.x > 0 || bounds.y > 0 else { return }
        let sign: CGFloat = naturalScrollPan ? 1 : -1
        imageOffset.width += sign * dx
        imageOffset.height -= sign * dy
        clampOffset()
    }

    private func clampOffset() {
        let bounds = panBounds()
        imageOffset.width = max(-bounds.x, min(bounds.x, imageOffset.width))
        imageOffset.height = max(-bounds.y, min(bounds.y, imageOffset.height))
    }

    private func panBounds() -> (x: CGFloat, y: CGFloat) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (0, 0)
        }
        let natural = CGSize(width: cgImage.width, height: cgImage.height)
        let bb = rotatedBoundingBox(natural, by: rotationAngle)
        let fitScale = min(containerSize.width / bb.width, containerSize.height / bb.height)
        let displayed = CGSize(
            width: bb.width * fitScale * zoomScale,
            height: bb.height * fitScale * zoomScale
        )
        return (
            x: max(0, (displayed.width - containerSize.width) / 2),
            y: max(0, (displayed.height - containerSize.height) / 2)
        )
    }
}
