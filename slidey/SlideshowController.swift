import Foundation

@Observable
final class SlideshowController {
    var isPlaying = false
    private var timer: Timer?

    func toggle(isProcessing: Bool, imageCount: Int, interval: Double, advance: @escaping () -> Void, onStart: (() -> Void)? = nil) {
        if isPlaying {
            stop()
        } else {
            start(isProcessing: isProcessing, imageCount: imageCount, interval: interval, advance: advance, onStart: onStart)
        }
    }

    func start(isProcessing: Bool, imageCount: Int, interval: Double, advance: @escaping () -> Void, onStart: (() -> Void)? = nil) {
        guard !isProcessing, imageCount > 1 else { return }
        isPlaying = true
        reschedule(interval: interval, advance: advance)
        onStart?()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func reschedule(interval: Double, advance: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            advance()
        }
    }
}
