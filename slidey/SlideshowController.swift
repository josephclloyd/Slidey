import Foundation

@Observable
final class SlideshowController {
    var isPlaying = false
    private var timer: Timer?
    private var shouldStop: (() -> Bool)?

    func toggle(isProcessing: Bool, imageCount: Int, interval: Double, advance: @escaping () -> Void, shouldStop: (() -> Bool)? = nil, onStart: (() -> Void)? = nil) {
        if isPlaying {
            stop()
        } else {
            start(isProcessing: isProcessing, imageCount: imageCount, interval: interval, advance: advance, shouldStop: shouldStop, onStart: onStart)
        }
    }

    func start(isProcessing: Bool, imageCount: Int, interval: Double, advance: @escaping () -> Void, shouldStop: (() -> Bool)? = nil, onStart: (() -> Void)? = nil) {
        guard !isProcessing, imageCount > 1 else { return }
        isPlaying = true
        self.shouldStop = shouldStop
        reschedule(interval: interval, advance: advance)
        onStart?()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        shouldStop = nil
    }

    func reschedule(interval: Double, advance: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            if self?.shouldStop?() == true {
                self?.stop()
            } else {
                advance()
            }
        }
    }
}
