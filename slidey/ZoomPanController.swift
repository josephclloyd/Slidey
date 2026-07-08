import SwiftUI
import AppKit

enum PanDirection {
    case left, right, up, down
}

// MARK: - SwipeTracker

struct SwipeTracker {
    private(set) var accumulatedX: CGFloat = 0
    private(set) var accumulatedY: CGFloat = 0
    private(set) var triggered: Bool = false

    static let threshold: CGFloat = 50.0

    mutating func began() {
        accumulatedX = 0
        accumulatedY = 0
        triggered = false
    }

    mutating func accumulate(dx: CGFloat, dy: CGFloat) -> Bool? {
        accumulatedX += dx
        accumulatedY += dy

        guard !triggered,
              abs(accumulatedX) > Self.threshold,
              abs(accumulatedX) > abs(accumulatedY) else {
            return nil
        }
        triggered = true
        return accumulatedX < 0
    }
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

    /// Zoom and pan so the given salient region (Vision normalized coords, bottom-left origin) fills the view.
    func zoomToSalientRegion(_ salientRect: CGRect, image: NSImage, rotationAngle: Angle) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              salientRect.width > 0, salientRect.height > 0 else { return }
        let naturalW = CGFloat(cgImage.width)
        let naturalH = CGFloat(cgImage.height)
        let fitScale = min(windowSize.width / naturalW, windowSize.height / naturalH)
        guard fitScale > 0, windowSize.width > 0 else { return }

        // Salient region size in display coords (at fit scale = zoomScale 1.0)
        let sDisplayW = salientRect.width * naturalW * fitScale
        let sDisplayH = salientRect.height * naturalH * fitScale
        guard sDisplayW > 0, sDisplayH > 0 else { return }

        // Zoom so the salient region fills most of the view (capped to avoid extreme zoom)
        let rawZoom = min(windowSize.width / sDisplayW, windowSize.height / sDisplayH)
        zoomScale = min(max(rawZoom, 1.0), 8.0)

        // Salient region center in image pixels, measured from image center
        // Vision y=0 is bottom; SwiftUI y=0 is top — flip y
        let pCenterX = (salientRect.midX - 0.5) * naturalW
        let pCenterY = (0.5 - salientRect.midY) * naturalH

        // Offset to center the salient region in the view
        imageOffset = CGSize(
            width: -(pCenterX * fitScale * zoomScale),
            height: -(pCenterY * fitScale * zoomScale)
        )
    }
}

// MARK: - ClickCatcher

struct ClickCatcher: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onZoom: (CGFloat) -> Void
    let onScroll: (CGFloat, CGFloat) -> Void
    var dragURL: URL? = nil
    var canDrag: Bool = false
    var onSwipeNavigate: ((Bool) -> Void)? = nil
    var swipeEnabled: Bool = false

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onZoom = onZoom
        view.onScroll = onScroll
        view.dragURL = dragURL
        view.canDrag = canDrag
        view.onSwipeNavigate = onSwipeNavigate
        view.swipeEnabled = swipeEnabled
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onZoom = onZoom
        nsView.onScroll = onScroll
        nsView.dragURL = dragURL
        nsView.canDrag = canDrag
        nsView.onSwipeNavigate = onSwipeNavigate
        nsView.swipeEnabled = swipeEnabled
    }
}

class ClickCatcherView: NSView, NSDraggingSource {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var dragURL: URL?
    var canDrag: Bool = false
    var onSwipeNavigate: ((Bool) -> Void)?
    var swipeEnabled: Bool = false

    private var mouseDownEvent: NSEvent?
    private var mouseDownLocation: NSPoint?
    private var didStartDrag = false
    private var swipeTracker = SwipeTracker()

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
            return
        }
        if canDrag, dragURL != nil {
            mouseDownEvent = event
            mouseDownLocation = event.locationInWindow
            didStartDrag = false
        } else {
            onLeftClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard canDrag, !didStartDrag,
              let startLocation = mouseDownLocation,
              let url = dragURL,
              let downEvent = mouseDownEvent else { return }
        let current = event.locationInWindow
        let dx = current.x - startLocation.x
        let dy = current.y - startLocation.y
        guard sqrt(dx * dx + dy * dy) > 4 else { return }

        didStartDrag = true
        mouseDownLocation = nil
        mouseDownEvent = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let iconSize = NSSize(width: 64, height: 64)
        icon.size = iconSize
        let viewPoint = convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(x: viewPoint.x - 32, y: viewPoint.y - 32, width: 64, height: 64),
            contents: icon
        )
        beginDraggingSession(with: [draggingItem], event: downEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownLocation != nil, !didStartDrag {
            onLeftClick?()
        }
        mouseDownLocation = nil
        mouseDownEvent = nil
        didStartDrag = false
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
        } else if swipeEnabled, event.phase != [] {
            handleSwipeTracking(event)
        } else if swipeEnabled, event.momentumPhase != [] {
            // Momentum after a swipe — ignore to prevent multi-skip
        } else {
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }

    private func handleSwipeTracking(_ event: NSEvent) {
        if event.phase.contains(.began) {
            swipeTracker.began()
        }
        if let isNext = swipeTracker.accumulate(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) {
            onSwipeNavigate?(isNext)
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
    var dragURL: URL? = nil
    var onSwipeNavigate: ((Bool) -> Void)? = nil
    var swipeEnabled: Bool = false

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
                    onScroll: { applyPan(dx: $0, dy: $1) },
                    dragURL: dragURL,
                    canDrag: abs(zoomScale - 1.0) < 0.01,
                    onSwipeNavigate: onSwipeNavigate,
                    swipeEnabled: swipeEnabled
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
