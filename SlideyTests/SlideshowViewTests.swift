import SwiftUI
import XCTest
@testable import Slidey

// MARK: - Helper

private func makeBitmapImage(width: Int, height: Int) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    return image
}

// MARK: - ZoomPanController Tests

final class ZoomPanControllerTests: XCTestCase {
    func testInitialState() {
        let controller = ZoomPanController()
        XCTAssertEqual(controller.zoomScale, 1.0)
        XCTAssertEqual(controller.imageOffset, .zero)
    }

    func testReset() {
        let controller = ZoomPanController()
        controller.zoomScale = 3.0
        controller.imageOffset = CGSize(width: 100, height: -50)
        controller.reset()
        XCTAssertEqual(controller.zoomScale, 1.0)
        XCTAssertEqual(controller.imageOffset, .zero)
    }

    func testCanPanReturnsFalseAtDefaultZoom() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        let image = makeBitmapImage(width: 400, height: 300)
        for dir in [PanDirection.left, .right, .up, .down] {
            XCTAssertFalse(controller.canPan(direction: dir, image: image, rotationAngle: .zero))
        }
    }

    func testCanPanReturnsFalseWithNilImage() {
        let controller = ZoomPanController()
        controller.zoomScale = 3.0
        controller.windowSize = CGSize(width: 800, height: 600)
        for dir in [PanDirection.left, .right, .up, .down] {
            XCTAssertFalse(controller.canPan(direction: dir, image: nil, rotationAngle: .zero))
        }
    }

    func testCanPanWhenZoomedWithRoomToMove() {
        let controller = ZoomPanController()
        controller.zoomScale = 3.0
        controller.windowSize = CGSize(width: 800, height: 600)
        controller.imageOffset = .zero
        let image = makeBitmapImage(width: 800, height: 600)
        XCTAssertTrue(controller.canPan(direction: .left, image: image, rotationAngle: .zero))
        XCTAssertTrue(controller.canPan(direction: .right, image: image, rotationAngle: .zero))
        XCTAssertTrue(controller.canPan(direction: .up, image: image, rotationAngle: .zero))
        XCTAssertTrue(controller.canPan(direction: .down, image: image, rotationAngle: .zero))
    }

    func testZoomToNativeSizeWithNilImageIsNoop() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        controller.zoomScale = 2.0
        controller.zoomToNativeSize(image: nil, rotationAngle: .zero)
        XCTAssertEqual(controller.zoomScale, 2.0)
    }

    func testZoomToNativeSize() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        let image = makeBitmapImage(width: 1600, height: 1200)
        controller.zoomToNativeSize(image: image, rotationAngle: .zero)
        let fitScale = min(800.0 / 1600.0, 600.0 / 1200.0)
        XCTAssertEqual(controller.zoomScale, 1.0 / fitScale, accuracy: 0.001)
        XCTAssertEqual(controller.imageOffset, .zero)
    }

    func testZoomToFillScreenLandscape() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        let image = makeBitmapImage(width: 1600, height: 800)
        controller.zoomToFillScreen(image: image, rotationAngle: .zero)
        let fitScale = min(800.0 / 1600.0, 600.0 / 800.0)
        let fillScale = 800.0 / 1600.0
        XCTAssertEqual(controller.zoomScale, fillScale / fitScale, accuracy: 0.001)
    }

    func testZoomToFillScreenPortrait() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        let image = makeBitmapImage(width: 400, height: 800)
        controller.zoomToFillScreen(image: image, rotationAngle: .zero)
        let bb = rotatedBoundingBox(CGSize(width: 400, height: 800), by: .zero)
        let fitScale = min(800.0 / bb.width, 600.0 / bb.height)
        let fillScale = 600.0 / bb.height
        XCTAssertEqual(controller.zoomScale, fillScale / fitScale, accuracy: 0.001)
    }

    func testZoomToFillScreenWithNilImageIsNoop() {
        let controller = ZoomPanController()
        controller.windowSize = CGSize(width: 800, height: 600)
        controller.zoomScale = 2.0
        controller.zoomToFillScreen(image: nil, rotationAngle: .zero)
        XCTAssertEqual(controller.zoomScale, 2.0)
    }
}

// MARK: - SlideshowController Tests

final class SlideshowControllerTests: XCTestCase {
    func testInitiallyNotPlaying() {
        let controller = SlideshowController()
        XCTAssertFalse(controller.isPlaying)
    }

    func testStartSetsIsPlaying() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        XCTAssertTrue(controller.isPlaying)
    }

    func testStopClearsIsPlaying() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        controller.stop()
        XCTAssertFalse(controller.isPlaying)
    }

    func testStopWhenNotPlayingIsNoop() {
        let controller = SlideshowController()
        controller.stop()
        XCTAssertFalse(controller.isPlaying)
    }

    func testToggleStartsWhenStopped() {
        let controller = SlideshowController()
        controller.toggle(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        XCTAssertTrue(controller.isPlaying)
    }

    func testToggleStopsWhenPlaying() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        controller.toggle(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        XCTAssertFalse(controller.isPlaying)
    }

    func testStartGuardsIsProcessing() {
        let controller = SlideshowController()
        controller.start(isProcessing: true, imageCount: 5, interval: 3.0, advance: {})
        XCTAssertFalse(controller.isPlaying)
    }

    func testStartGuardsSingleImage() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 1, interval: 3.0, advance: {})
        XCTAssertFalse(controller.isPlaying)
    }

    func testStartGuardsEmptyImages() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 0, interval: 3.0, advance: {})
        XCTAssertFalse(controller.isPlaying)
    }

    func testStartCallsOnStart() {
        let controller = SlideshowController()
        var called = false
        controller.start(isProcessing: false, imageCount: 5, interval: 3.0, advance: {}, onStart: { called = true })
        XCTAssertTrue(called)
    }

    func testStartDoesNotCallOnStartWhenGuarded() {
        let controller = SlideshowController()
        var called = false
        controller.start(isProcessing: true, imageCount: 5, interval: 3.0, advance: {}, onStart: { called = true })
        XCTAssertFalse(called)
    }

    func testShouldStopTrueStopsSlideshow() {
        let controller = SlideshowController()
        let stopped = expectation(description: "slideshow stopped")
        var advanceCount = 0
        controller.start(
            isProcessing: false, imageCount: 5, interval: 0.05,
            advance: { advanceCount += 1 },
            shouldStop: { true }
        )
        XCTAssertTrue(controller.isPlaying)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2.0)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(advanceCount, 0)
    }

    func testShouldStopFalseAdvancesNormally() {
        let controller = SlideshowController()
        let advanced = expectation(description: "advanced at least once")
        var fulfilled = false
        controller.start(
            isProcessing: false, imageCount: 5, interval: 0.05,
            advance: {
                if !fulfilled { fulfilled = true; advanced.fulfill() }
            },
            shouldStop: { false }
        )
        wait(for: [advanced], timeout: 2.0)
        XCTAssertTrue(controller.isPlaying)
        controller.stop()
    }

    func testNilShouldStopAdvancesNormally() {
        let controller = SlideshowController()
        let advanced = expectation(description: "advanced at least once")
        var fulfilled = false
        controller.start(
            isProcessing: false, imageCount: 5, interval: 0.05,
            advance: {
                if !fulfilled { fulfilled = true; advanced.fulfill() }
            }
        )
        wait(for: [advanced], timeout: 2.0)
        XCTAssertTrue(controller.isPlaying)
        controller.stop()
    }

    func testLoopDisabledStopsAtLastImage() {
        let controller = SlideshowController()
        let stopped = expectation(description: "slideshow stopped")
        let currentIndex = 4
        let imageCount = 5
        var advanceCount = 0
        controller.start(
            isProcessing: false, imageCount: imageCount, interval: 0.05,
            advance: { advanceCount += 1 },
            shouldStop: { currentIndex >= imageCount - 1 }
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2.0)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(advanceCount, 0)
    }

    func testLoopEnabledWrapsFromLastImage() {
        let controller = SlideshowController()
        let advanced = expectation(description: "advanced at least once")
        var currentIndex = 4
        let imageCount = 5
        var fulfilled = false
        controller.start(
            isProcessing: false, imageCount: imageCount, interval: 0.05,
            advance: {
                currentIndex = (currentIndex + 1) % imageCount
                if !fulfilled { fulfilled = true; advanced.fulfill() }
            },
            shouldStop: { false }
        )
        wait(for: [advanced], timeout: 2.0)
        XCTAssertTrue(controller.isPlaying)
        controller.stop()
    }

    func testShouldStopCheckedEachTick() {
        let controller = SlideshowController()
        let stopped = expectation(description: "slideshow stopped after advancing")
        var currentIndex = 0
        let imageCount = 3
        var advanceCount = 0
        controller.start(
            isProcessing: false, imageCount: imageCount, interval: 0.05,
            advance: {
                advanceCount += 1
                currentIndex += 1
            },
            shouldStop: {
                let shouldStop = currentIndex >= imageCount - 1
                if shouldStop { stopped.fulfill() }
                return shouldStop
            }
        )
        wait(for: [stopped], timeout: 2.0)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(advanceCount, 2)
    }
}

// MARK: - Launch State Guardrails

final class LaunchStateGuardrailTests: XCTestCase {
    func testIsPlayingIsNotPersistedInUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "isPlaying")

        let controller = SlideshowController()
        XCTAssertFalse(controller.isPlaying)

        defaults.set(true, forKey: "isPlaying")
        let fresh = SlideshowController()
        XCTAssertFalse(fresh.isPlaying, "isPlaying must not read from UserDefaults")
        defaults.removeObject(forKey: "isPlaying")
    }

    func testStopAfterStartResetsToPaused() {
        let controller = SlideshowController()
        controller.start(isProcessing: false, imageCount: 5, interval: 3.0, advance: {})
        XCTAssertTrue(controller.isPlaying)
        controller.stop()
        XCTAssertFalse(controller.isPlaying, "stop() must always leave slideshow paused")
    }
}

// MARK: - Manual Navigation Always Wraps

final class ManualNavigationWrapTests: XCTestCase {
    func testNextImageWrapsFromLastToFirst() {
        let loader = ImageLoader()
        loader.imageURLs = (0..<5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }
        loader.currentIndex = 4
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testPreviousImageWrapsFromFirstToLast() {
        let loader = ImageLoader()
        loader.imageURLs = (0..<5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }
        loader.currentIndex = 0
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 4)
    }

    func testNextImageWrapsRegardlessOfLoopSetting() {
        UserDefaults.standard.set(false, forKey: "slideshowLoop")
        defer { UserDefaults.standard.removeObject(forKey: "slideshowLoop") }
        let loader = ImageLoader()
        loader.imageURLs = (0..<5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }
        loader.currentIndex = 4
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testPreviousImageWrapsRegardlessOfLoopSetting() {
        UserDefaults.standard.set(false, forKey: "slideshowLoop")
        defer { UserDefaults.standard.removeObject(forKey: "slideshowLoop") }
        let loader = ImageLoader()
        loader.imageURLs = (0..<5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }
        loader.currentIndex = 0
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 4)
    }
}

// MARK: - rotatedBoundingBox Tests

final class RotatedBoundingBoxTests: XCTestCase {
    func testZeroRotation() {
        let result = rotatedBoundingBox(CGSize(width: 200, height: 100), by: .zero)
        XCTAssertEqual(result.width, 200, accuracy: 0.001)
        XCTAssertEqual(result.height, 100, accuracy: 0.001)
    }

    func test90DegreeRotation() {
        let result = rotatedBoundingBox(CGSize(width: 200, height: 100), by: Angle(degrees: 90))
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 200, accuracy: 0.001)
    }

    func test180DegreeRotation() {
        let result = rotatedBoundingBox(CGSize(width: 200, height: 100), by: Angle(degrees: 180))
        XCTAssertEqual(result.width, 200, accuracy: 0.001)
        XCTAssertEqual(result.height, 100, accuracy: 0.001)
    }

    func test270DegreeRotation() {
        let result = rotatedBoundingBox(CGSize(width: 200, height: 100), by: Angle(degrees: 270))
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 200, accuracy: 0.001)
    }

    func test45DegreeRotation() {
        let size = CGSize(width: 200, height: 100)
        let result = rotatedBoundingBox(size, by: Angle(degrees: 45))
        let c = abs(cos(Double.pi / 4))
        let s = abs(sin(Double.pi / 4))
        let expectedW = 200 * c + 100 * s
        let expectedH = 200 * s + 100 * c
        XCTAssertEqual(result.width, expectedW, accuracy: 0.001)
        XCTAssertEqual(result.height, expectedH, accuracy: 0.001)
    }

    func testSquareIsUnchangedByRotation() {
        let result = rotatedBoundingBox(CGSize(width: 100, height: 100), by: Angle(degrees: 45))
        XCTAssertEqual(result.width, result.height, accuracy: 0.001)
    }
}

// MARK: - Navigation: Home/End + per-URL keying invariant

final class NavigationURLKeyingTests: XCTestCase {
    var loader: ImageLoader!
    let urls = (0..<5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }

    override func setUp() {
        super.setUp()
        loader = ImageLoader()
        loader.imageURLs = urls
        loader.currentIndex = 0
    }

    func testJumpToFirstImage() {
        loader.currentIndex = 3
        loader.jumpTo(index: 0)
        XCTAssertEqual(loader.currentIndex, 0)
        XCTAssertEqual(loader.currentImageURL, urls[0])
    }

    func testJumpToLastImage() {
        loader.jumpTo(index: urls.count - 1)
        XCTAssertEqual(loader.currentIndex, 4)
        XCTAssertEqual(loader.currentImageURL, urls[4])
    }

    func testJumpToFirstWhenAlreadyFirst() {
        loader.currentIndex = 0
        loader.jumpTo(index: 0)
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testJumpToLastWhenAlreadyLast() {
        loader.currentIndex = 4
        loader.jumpTo(index: urls.count - 1)
        XCTAssertEqual(loader.currentIndex, 4)
    }

    func testJumpToEndMinusOneOnEmptyIsNoop() {
        loader.imageURLs = []
        loader.jumpTo(index: -1)
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testCurrentURLSurvivesRemovalBefore() {
        loader.currentIndex = 3
        let urlBeforeRemoval = loader.currentImageURL
        loader.removeImage(at: urls[1])
        XCTAssertEqual(loader.currentImageURL, urlBeforeRemoval)
    }

    func testCurrentURLSurvivesRemovalAfter() {
        loader.currentIndex = 1
        let urlBeforeRemoval = loader.currentImageURL
        loader.removeImage(at: urls[3])
        XCTAssertEqual(loader.currentImageURL, urlBeforeRemoval)
    }

    func testCurrentURLSurvivesMultipleRemovals() {
        loader.currentIndex = 2
        let targetURL = loader.currentImageURL
        loader.removeImage(at: urls[0])
        loader.removeImage(at: urls[4])
        XCTAssertEqual(loader.currentImageURL, targetURL)
    }

    func testNavigationCycleReturnsToSameURLs() {
        let startURL = loader.currentImageURL
        for _ in 0..<urls.count {
            loader.nextImage()
        }
        XCTAssertEqual(loader.currentImageURL, startURL)
    }

    func testBackwardCycleReturnsToSameURL() {
        let startURL = loader.currentImageURL
        for _ in 0..<urls.count {
            loader.previousImage()
        }
        XCTAssertEqual(loader.currentImageURL, startURL)
    }

    func testSingleImageNextStaysOnSame() {
        loader.imageURLs = [urls[0]]
        loader.currentIndex = 0
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
        XCTAssertEqual(loader.currentImageURL, urls[0])
    }

    func testSingleImagePreviousStaysOnSame() {
        loader.imageURLs = [urls[0]]
        loader.currentIndex = 0
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 0)
        XCTAssertEqual(loader.currentImageURL, urls[0])
    }

    func testURLFilterPreservesCurrentURL() {
        loader.imageURLs = urls
        loader.currentIndex = 2
        let targetURL = urls[2]
        let kept = Set([urls[0], urls[2], urls[4]].map { $0.absoluteString })
        loader.imageURLs = urls.filter { kept.contains($0.absoluteString) }
        if let idx = loader.imageURLs.firstIndex(of: targetURL) {
            loader.currentIndex = idx
        }
        XCTAssertEqual(loader.currentImageURL, targetURL)
    }
}


final class ThumbnailCacheTests: XCTestCase {
    func testSetAndGet() {
        let cache = ThumbnailCache(countLimit: 10)
        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        let image = NSImage(size: NSSize(width: 100, height: 100))

        cache.set(url, image: image)
        XCTAssertNotNil(cache.get(url))
    }

    func testMissReturnsNil() {
        let cache = ThumbnailCache(countLimit: 10)
        let url = URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        XCTAssertNil(cache.get(url))
    }

    func testDifferentURLsAreSeparate() {
        let cache = ThumbnailCache(countLimit: 10)
        let url1 = URL(fileURLWithPath: "/tmp/a.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/b.jpg")
        let image = NSImage(size: NSSize(width: 100, height: 100))

        cache.set(url1, image: image)

        XCTAssertNotNil(cache.get(url1))
        XCTAssertNil(cache.get(url2))
    }

    func testOverwriteSameKey() {
        let cache = ThumbnailCache(countLimit: 10)
        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        let image1 = NSImage(size: NSSize(width: 50, height: 50))
        let image2 = NSImage(size: NSSize(width: 200, height: 200))

        cache.set(url, image: image1)
        cache.set(url, image: image2)

        let retrieved = cache.get(url)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.size.width, 200)
    }

    func testCountLimitIsRespected() {
        let cache = ThumbnailCache(countLimit: 3)

        for i in 0..<10 {
            let url = URL(fileURLWithPath: "/tmp/img\(i).jpg")
            cache.set(url, image: NSImage(size: NSSize(width: 10, height: 10)))
        }

        var hitCount = 0
        for i in 0..<10 {
            let url = URL(fileURLWithPath: "/tmp/img\(i).jpg")
            if cache.get(url) != nil { hitCount += 1 }
        }
        XCTAssertLessThanOrEqual(hitCount, 3)
    }
}

// MARK: - ImageDimensions & TitleForImage Tests

final class ImageDimensionsTests: XCTestCase {
    private func createTempJPEG(width: Int, height: Int) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let data = rep.representation(using: .jpeg, properties: [:])!
        try? data.write(to: url)
        return url
    }

    override func tearDown() {
        try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jpg" }
         .forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    func testValidImageReturnsDimensions() {
        let url = createTempJPEG(width: 10, height: 20)
        let dims = SlideshowView.imageDimensions(for: url)
        XCTAssertNotNil(dims)
        XCTAssertEqual(dims?.width, 10)
        XCTAssertEqual(dims?.height, 20)
    }

    func testNonExistentURLReturnsNil() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).jpg")
        XCTAssertNil(SlideshowView.imageDimensions(for: url))
    }

    func testZeroByteFileReturnsNil() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        XCTAssertNil(SlideshowView.imageDimensions(for: url))
    }

    func testTitleForImageWithDimensions() {
        let url = createTempJPEG(width: 10, height: 20)
        let title = SlideshowView.titleForImage(at: url)
        XCTAssertTrue(title.hasSuffix("(10×20)"))
        XCTAssertTrue(title.hasPrefix(url.lastPathComponent.replacingOccurrences(of: " (10×20)", with: "")))
    }

    func testTitleForImageFallsBackWithoutDimensions() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).jpg")
        let title = SlideshowView.titleForImage(at: url)
        XCTAssertEqual(title, url.lastPathComponent)
    }
}

// MARK: - validateRenameTarget Tests

final class ValidateRenameTargetTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testValidNameReturnsNil() {
        let result = validateRenameTarget(newName: "newname", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNil(result)
    }

    func testEmptyNameReturnsNil() {
        let result = validateRenameTarget(newName: "", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNil(result)
    }

    func testWhitespaceOnlyReturnsNil() {
        let result = validateRenameTarget(newName: "   ", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNil(result)
    }

    func testSameNameReturnsNil() {
        let result = validateRenameTarget(newName: "original", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNil(result)
    }

    func testSlashReturnsError() {
        let result = validateRenameTarget(newName: "bad/name", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("/"))
    }

    func testColonReturnsError() {
        let result = validateRenameTarget(newName: "bad:name", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(":"))
    }

    func testExistingFileReturnsError() {
        let existingFile = tempDir.appendingPathComponent("conflict.jpg")
        FileManager.default.createFile(atPath: existingFile.path, contents: Data())

        let result = validateRenameTarget(newName: "conflict", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("already exists"))
    }

    func testNonExistingFileReturnsNil() {
        let result = validateRenameTarget(newName: "unique-name", ext: "png", directory: tempDir, originalBasename: "original")
        XCTAssertNil(result)
    }

    func testTrimsWhitespaceBeforeValidating() {
        let existingFile = tempDir.appendingPathComponent("padded.jpg")
        FileManager.default.createFile(atPath: existingFile.path, contents: Data())

        let result = validateRenameTarget(newName: "  padded  ", ext: "jpg", directory: tempDir, originalBasename: "original")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("already exists"))
    }
}
