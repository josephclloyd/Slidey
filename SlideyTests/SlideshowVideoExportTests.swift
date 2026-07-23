import XCTest
@testable import Slidey

final class SlideshowVideoExportTests: XCTestCase {

    // MARK: - Frame counts

    func testHoldFrameCountRoundsToNearest() {
        XCTAssertEqual(SlideshowVideoFramePlan.holdFrameCount(seconds: 5, fps: 30), 150)
        XCTAssertEqual(SlideshowVideoFramePlan.holdFrameCount(seconds: 0.5, fps: 30), 15)
        XCTAssertEqual(SlideshowVideoFramePlan.holdFrameCount(seconds: 1.0 / 30.0, fps: 30), 1)
    }

    func testHoldFrameCountNeverZero() {
        XCTAssertEqual(SlideshowVideoFramePlan.holdFrameCount(seconds: 0, fps: 30), 1)
    }

    func testTransitionFrameCountDisabledIsZero() {
        XCTAssertEqual(
            SlideshowVideoFramePlan.transitionFrameCount(enabled: false, duration: 0.3, fps: 30), 0
        )
    }

    func testTransitionFrameCountEnabled() {
        XCTAssertEqual(
            SlideshowVideoFramePlan.transitionFrameCount(enabled: true, duration: 0.3, fps: 30), 9
        )
    }

    func testTransitionFrameCountEnabledNeverZero() {
        XCTAssertEqual(
            SlideshowVideoFramePlan.transitionFrameCount(enabled: true, duration: 0, fps: 30), 1
        )
    }

    // MARK: - Total frames

    func testTotalFramesWithHardCut() {
        let plan = SlideshowVideoFramePlan(imageCount: 3, holdFrames: 150, transitionFrames: 0)
        XCTAssertEqual(plan.totalFrames, 450)
    }

    func testTotalFramesWithTransitions() {
        // 3 holds of 150 + 2 transitions of 9 = 450 + 18
        let plan = SlideshowVideoFramePlan(imageCount: 3, holdFrames: 150, transitionFrames: 9)
        XCTAssertEqual(plan.totalFrames, 468)
    }

    func testTotalFramesEmpty() {
        let plan = SlideshowVideoFramePlan(imageCount: 0, holdFrames: 150, transitionFrames: 9)
        XCTAssertEqual(plan.totalFrames, 0)
        XCTAssertTrue(plan.frames().isEmpty)
    }

    func testTotalFramesSingleImageHasNoTransition() {
        let plan = SlideshowVideoFramePlan(imageCount: 1, holdFrames: 150, transitionFrames: 9)
        XCTAssertEqual(plan.totalFrames, 150)
        XCTAssertEqual(plan.frames().count, 150)
        XCTAssertTrue(plan.frames().allSatisfy { $0.overlay == nil })
    }

    // MARK: - Frame ordering

    func testFrameOrderingHardCut() {
        let plan = SlideshowVideoFramePlan(imageCount: 2, holdFrames: 2, transitionFrames: 0)
        let frames = plan.frames()
        XCTAssertEqual(frames, [
            .init(base: 0, overlay: nil, blend: 0),
            .init(base: 0, overlay: nil, blend: 0),
            .init(base: 1, overlay: nil, blend: 0),
            .init(base: 1, overlay: nil, blend: 0)
        ])
    }

    func testFrameOrderingWithTransition() {
        let plan = SlideshowVideoFramePlan(imageCount: 2, holdFrames: 1, transitionFrames: 2)
        let frames = plan.frames()
        XCTAssertEqual(frames, [
            .init(base: 0, overlay: nil, blend: 0),
            .init(base: 0, overlay: 1, blend: 0.5),
            .init(base: 0, overlay: 1, blend: 1.0),
            .init(base: 1, overlay: nil, blend: 0)
        ])
    }

    func testTransitionsBlendMonotonicallyToOne() {
        let plan = SlideshowVideoFramePlan(imageCount: 2, holdFrames: 1, transitionFrames: 4)
        let transitionBlends = plan.frames().compactMap { $0.overlay != nil ? $0.blend : nil }
        XCTAssertEqual(transitionBlends, [0.25, 0.5, 0.75, 1.0])
    }

    func testEveryImageAppearsAsBaseInOrder() {
        let plan = SlideshowVideoFramePlan(imageCount: 4, holdFrames: 3, transitionFrames: 2)
        let holdBases = plan.frames().compactMap { $0.overlay == nil ? $0.base : nil }
        // Each of the 4 images held 3 times, in ascending order.
        XCTAssertEqual(holdBases, [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3])
    }
}
