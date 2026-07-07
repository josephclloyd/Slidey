import Combine
import CoreImage
import SwiftUI
import XCTest
@testable import Slidey

final class PendingOpensTests: XCTestCase {
    func testInitialStateIsNil() {
        let opens = PendingOpens()
        XCTAssertNil(opens.pending)
    }

    func testSendPublishesURL() {
        let opens = PendingOpens()
        let url = URL(fileURLWithPath: "/tmp/test")
        let expectation = expectation(description: "pending updated")

        let cancellable = opens.$pending
            .dropFirst()
            .sink { value in
                if value == url {
                    expectation.fulfill()
                }
            }

        opens.send(url)
        waitForExpectations(timeout: 1)
        _ = cancellable
    }
}

// MARK: - Settings @AppStorage round-trip tests

final class SettingsRoundTripTests: XCTestCase {
    private let suiteName = "SettingsRoundTripTests_\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMusicModeRoundTrip() {
        defaults.set("song", forKey: "musicMode")
        XCTAssertEqual(defaults.string(forKey: "musicMode"), "song")

        defaults.set("playlist", forKey: "musicMode")
        XCTAssertEqual(defaults.string(forKey: "musicMode"), "playlist")

        defaults.set("random", forKey: "musicMode")
        XCTAssertEqual(defaults.string(forKey: "musicMode"), "random")

        defaults.set("off", forKey: "musicMode")
        XCTAssertEqual(defaults.string(forKey: "musicMode"), "off")
    }

    func testMusicModeDefaultIsOff() {
        XCTAssertNil(defaults.string(forKey: "musicMode"))
        let mode = defaults.string(forKey: "musicMode") ?? "off"
        XCTAssertEqual(mode, "off")
    }

    func testMusicModeEnumRawValueConsistency() {
        for mode in [MusicMode.off, .song, .playlist, .random] {
            defaults.set(mode.rawValue, forKey: "musicMode")
            let stored = defaults.string(forKey: "musicMode")!
            XCTAssertEqual(MusicMode(rawValue: stored), mode)
        }
    }

    func testSlideshowIntervalRoundTrip() {
        defaults.set(10.0, forKey: "slideshowInterval")
        XCTAssertEqual(defaults.double(forKey: "slideshowInterval"), 10.0)
    }

    func testSlideshowIntervalDefaultIs5() {
        let interval = defaults.object(forKey: "slideshowInterval") as? Double ?? 5.0
        XCTAssertEqual(interval, 5.0)
    }

    func testSlideshowIntervalBoundaryValues() {
        defaults.set(1.0, forKey: "slideshowInterval")
        XCTAssertEqual(defaults.double(forKey: "slideshowInterval"), 1.0)

        defaults.set(60.0, forKey: "slideshowInterval")
        XCTAssertEqual(defaults.double(forKey: "slideshowInterval"), 60.0)
    }

    func testTransitionsEnabledRoundTrip() {
        defaults.set(true, forKey: "transitionsEnabled")
        XCTAssertTrue(defaults.bool(forKey: "transitionsEnabled"))

        defaults.set(false, forKey: "transitionsEnabled")
        XCTAssertFalse(defaults.bool(forKey: "transitionsEnabled"))
    }

    func testTransitionsEnabledDefaultIsFalse() {
        XCTAssertFalse(defaults.bool(forKey: "transitionsEnabled"))
    }

    func testTransitionDurationRoundTrip() {
        defaults.set(1.5, forKey: "transitionDuration")
        XCTAssertEqual(defaults.double(forKey: "transitionDuration"), 1.5, accuracy: 0.001)
    }

    func testTransitionDurationDefaultIs0_3() {
        let duration = defaults.object(forKey: "transitionDuration") as? Double ?? 0.3
        XCTAssertEqual(duration, 0.3, accuracy: 0.001)
    }

    func testAutoOpenRecentRoundTrip() {
        defaults.set(false, forKey: "autoOpenRecent")
        XCTAssertFalse(defaults.bool(forKey: "autoOpenRecent"))

        defaults.set(true, forKey: "autoOpenRecent")
        XCTAssertTrue(defaults.bool(forKey: "autoOpenRecent"))
    }

    func testAutoPlayMusicRoundTrip() {
        defaults.set(false, forKey: "autoPlayMusic")
        XCTAssertFalse(defaults.bool(forKey: "autoPlayMusic"))

        defaults.set(true, forKey: "autoPlayMusic")
        XCTAssertTrue(defaults.bool(forKey: "autoPlayMusic"))
    }

    func testNaturalScrollPanRoundTrip() {
        defaults.set(true, forKey: "naturalScrollPan")
        XCTAssertTrue(defaults.bool(forKey: "naturalScrollPan"))
    }

    func testNaturalScrollPanDefaultIsFalse() {
        XCTAssertFalse(defaults.bool(forKey: "naturalScrollPan"))
    }

    func testSortOrderRoundTrip() {
        for order in AppSortOrder.allCases {
            defaults.set(order.rawValue, forKey: "sortOrder")
            let stored = defaults.string(forKey: "sortOrder")!
            XCTAssertEqual(AppSortOrder(rawValue: stored), order)
        }
    }

    func testLastMusicModeRoundTrip() {
        defaults.set("song", forKey: "lastMusicMode")
        XCTAssertEqual(defaults.string(forKey: "lastMusicMode"), "song")
    }

    func testMusicSongTitleRoundTrip() {
        defaults.set("My Favorite Song", forKey: "musicSongTitle")
        XCTAssertEqual(defaults.string(forKey: "musicSongTitle"), "My Favorite Song")
    }

    func testMusicPlaylistNameRoundTrip() {
        defaults.set("Chill Vibes", forKey: "musicPlaylistName")
        XCTAssertEqual(defaults.string(forKey: "musicPlaylistName"), "Chill Vibes")
    }
}

// MARK: - Music menu notification wiring tests

final class MusicMenuNotificationTests: XCTestCase {
    func testMusicOffNotificationFires() {
        let expectation = expectation(description: "musicOff notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .musicOff, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .musicOff, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testMusicChooseSongNotificationFires() {
        let expectation = expectation(description: "musicChooseSong notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .musicChooseSong, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .musicChooseSong, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testMusicChoosePlaylistNotificationFires() {
        let expectation = expectation(description: "musicChoosePlaylist notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .musicChoosePlaylist, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .musicChoosePlaylist, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testMusicShuffleNotificationFires() {
        let expectation = expectation(description: "musicShuffle notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .musicShuffle, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .musicShuffle, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testMusicNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.musicOff.rawValue, "MusicOff")
        XCTAssertEqual(NSNotification.Name.musicChooseSong.rawValue, "MusicChooseSong")
        XCTAssertEqual(NSNotification.Name.musicChoosePlaylist.rawValue, "MusicChoosePlaylist")
        XCTAssertEqual(NSNotification.Name.musicShuffle.rawValue, "MusicShuffle")
    }

    func testAllMusicNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [
            .musicOff, .musicChooseSong, .musicChoosePlaylist, .musicShuffle
        ]
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, names.count)
    }
}

// MARK: - File menu notification wiring tests (copy/move to folder)

final class FileMenuNotificationTests: XCTestCase {
    func testCopyToFolderNotificationFires() {
        let expectation = expectation(description: "copyToFolder notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .copyToFolder, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .copyToFolder, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testMoveToFolderNotificationFires() {
        let expectation = expectation(description: "moveToFolder notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .moveToFolder, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .moveToFolder, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testExportVisibleImagesNotificationFires() {
        let expectation = expectation(description: "exportVisibleImages notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .exportVisibleImages, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .exportVisibleImages, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testCopyMoveNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.copyToFolder.rawValue, "CopyToFolder")
        XCTAssertEqual(NSNotification.Name.moveToFolder.rawValue, "MoveToFolder")
        XCTAssertEqual(NSNotification.Name.exportVisibleImages.rawValue, "ExportVisibleImages")
    }

    func testCopyMoveNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [.copyToFolder, .moveToFolder, .moveToTrash, .exportVisibleImages]
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, names.count)
    }
}

// MARK: - Upscale notification wiring tests

final class UpscaleNotificationTests: XCTestCase {
    func testUpscale2xNotificationFires() {
        let expectation = expectation(description: "upscaleImage2x notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .upscaleImage2x, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .upscaleImage2x, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testUpscale4xNotificationFires() {
        let expectation = expectation(description: "upscaleImage4x notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .upscaleImage4x, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .upscaleImage4x, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testRemoveUpscalingNotificationFires() {
        let expectation = expectation(description: "removeUpscaling notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .removeUpscaling, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .removeUpscaling, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testUpscaleNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.upscaleImage2x.rawValue, "UpscaleImage2x")
        XCTAssertEqual(NSNotification.Name.upscaleImage4x.rawValue, "UpscaleImage4x")
        XCTAssertEqual(NSNotification.Name.removeUpscaling.rawValue, "RemoveUpscaling")
    }

    func testUpscaleNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [.upscaleImage2x, .upscaleImage4x, .removeUpscaling]
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, names.count)
    }
}

// MARK: - Denoise notification wiring tests

final class DenoiseNotificationTests: XCTestCase {
    func testDenoiseImageNotificationFires() {
        let expectation = expectation(description: "denoiseImage notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .denoiseImage, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .denoiseImage, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testDenoiseNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.denoiseImage.rawValue, "DenoiseImage")
    }

    func testDenoiseURLLevelsRoundTrip() {
        let suiteName = "DenoiseURLLevelsTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let levels: [String: Double] = ["file:///test/a.jpg": 45.0, "file:///test/b.jpg": 72.0]
        defaults.set(levels, forKey: "denoiseURLLevels")
        let stored = defaults.dictionary(forKey: "denoiseURLLevels") as? [String: Double] ?? [:]
        XCTAssertEqual(stored["file:///test/a.jpg"], 45.0)
        XCTAssertEqual(stored["file:///test/b.jpg"], 72.0)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Sharpen notification wiring tests

final class SharpenNotificationTests: XCTestCase {
    func testSharpenImageNotificationFires() {
        let expectation = expectation(description: "sharpenImage notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .sharpenImage, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .sharpenImage, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testRemoveSharpeningNotificationFires() {
        let expectation = expectation(description: "removeSharpening notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .removeSharpening, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .removeSharpening, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testSharpenNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.sharpenImage.rawValue, "SharpenImage")
        XCTAssertEqual(NSNotification.Name.removeSharpening.rawValue, "RemoveSharpening")
    }

    func testSharpenNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [.sharpenImage, .removeSharpening]
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, names.count)
    }
}

// MARK: - Slideshow menu notification wiring tests

final class SlideshowMenuNotificationTests: XCTestCase {
    func testToggleSlideshowNotificationFires() {
        let expectation = expectation(description: "toggleSlideshow notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleSlideshow, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .toggleSlideshow, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testToggleThumbnailsNotificationFires() {
        let expectation = expectation(description: "toggleThumbnails notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleThumbnails, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .toggleThumbnails, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testToggleImageInfoNotificationFires() {
        let expectation = expectation(description: "toggleImageInfo notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleImageInfo, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .toggleImageInfo, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testSlideshowNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.toggleSlideshow.rawValue, "ToggleSlideshow")
        XCTAssertEqual(NSNotification.Name.toggleThumbnails.rawValue, "ToggleThumbnails")
        XCTAssertEqual(NSNotification.Name.toggleImageInfo.rawValue, "ToggleImageInfo")
    }
}

// MARK: - Photo effects notification and persistence tests

final class PhotoEffectsTests: XCTestCase {
    func testApplyPhotoEffectNotificationFiresWithFilterName() {
        let expectation = expectation(description: "applyPhotoEffect fires with filter name")
        let observer = NotificationCenter.default.addObserver(
            forName: .applyPhotoEffect, object: nil, queue: .main
        ) { note in
            XCTAssertEqual(note.object as? String, "CIPhotoEffectMono")
            expectation.fulfill()
        }
        NotificationCenter.default.post(name: .applyPhotoEffect, object: "CIPhotoEffectMono")
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testApplyPhotoEffectNotificationFiresWithNilForNone() {
        let expectation = expectation(description: "applyPhotoEffect fires with nil for None")
        let observer = NotificationCenter.default.addObserver(
            forName: .applyPhotoEffect, object: nil, queue: .main
        ) { note in
            XCTAssertNil(note.object)
            expectation.fulfill()
        }
        NotificationCenter.default.post(name: .applyPhotoEffect, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testPhotoEffectNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.applyPhotoEffect.rawValue, "ApplyPhotoEffect")
    }

    func testPhotoEffectsUserDefaultsRoundTrip() {
        let suiteName = "PhotoEffectsTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let effects: [String: String] = [
            "file:///test/a.jpg": "CIPhotoEffectMono",
            "file:///test/b.jpg": "CIPhotoEffectFade"
        ]
        defaults.set(effects, forKey: "photoEffects")
        let stored = defaults.dictionary(forKey: "photoEffects") as? [String: String] ?? [:]
        XCTAssertEqual(stored["file:///test/a.jpg"], "CIPhotoEffectMono")
        XCTAssertEqual(stored["file:///test/b.jpg"], "CIPhotoEffectFade")
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testAllCIPhotoEffectFiltersAreValid() {
        let filterNames = [
            "CIPhotoEffectMono", "CIPhotoEffectNoir", "CIPhotoEffectFade",
            "CIPhotoEffectChrome", "CIPhotoEffectProcess", "CIPhotoEffectTonal"
        ]
        for name in filterNames {
            XCTAssertNotNil(CIFilter(name: name), "\(name) should be a valid CIFilter")
        }
    }
}

// MARK: - Flip notification tests

final class FlipNotificationTests: XCTestCase {
    func testFlipHorizontalNotificationFires() {
        let expectation = expectation(description: "flipHorizontal fires")
        let observer = NotificationCenter.default.addObserver(forName: .flipHorizontal, object: nil, queue: .main) { _ in expectation.fulfill() }
        NotificationCenter.default.post(name: .flipHorizontal, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testFlipVerticalNotificationFires() {
        let expectation = expectation(description: "flipVertical fires")
        let observer = NotificationCenter.default.addObserver(forName: .flipVertical, object: nil, queue: .main) { _ in expectation.fulfill() }
        NotificationCenter.default.post(name: .flipVertical, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testFlipNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.flipHorizontal.rawValue, "FlipHorizontal")
        XCTAssertEqual(NSNotification.Name.flipVertical.rawValue, "FlipVertical")
    }
}

// MARK: - Vignette notification and persistence tests

final class VignetteNotificationTests: XCTestCase {
    func testVignetteImageNotificationFires() {
        let expectation = expectation(description: "vignetteImage fires")
        let observer = NotificationCenter.default.addObserver(forName: .vignetteImage, object: nil, queue: .main) { _ in expectation.fulfill() }
        NotificationCenter.default.post(name: .vignetteImage, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testVignetteNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.vignetteImage.rawValue, "VignetteImage")
    }

    func testVignetteURLLevelsRoundTrip() {
        let suiteName = "VignetteURLLevelsTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let levels: [String: Double] = ["file:///test/a.jpg": 0.8, "file:///test/b.jpg": 1.5]
        defaults.set(levels, forKey: "vignetteURLLevels")
        let stored = defaults.dictionary(forKey: "vignetteURLLevels") as? [String: Double] ?? [:]
        XCTAssertEqual(stored["file:///test/a.jpg"] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(stored["file:///test/b.jpg"] ?? 0, 1.5, accuracy: 0.001)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testCIVignetteEffectFilterIsValid() {
        XCTAssertNotNil(CIFilter(name: "CIVignetteEffect"))
    }
}

// MARK: - Adjustments notification and persistence tests

final class AdjustmentsNotificationTests: XCTestCase {
    func testAdjustmentsImageNotificationFires() {
        let expectation = expectation(description: "adjustmentsImage fires")
        let observer = NotificationCenter.default.addObserver(forName: .adjustmentsImage, object: nil, queue: .main) { _ in expectation.fulfill() }
        NotificationCenter.default.post(name: .adjustmentsImage, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testAdjustmentsNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.adjustmentsImage.rawValue, "AdjustmentsImage")
    }

    func testImageAdjustmentsDefaultIsIdentity() {
        let adj = SlideshowView.ImageAdjustments()
        XCTAssertTrue(adj.isIdentity)
        XCTAssertEqual(adj.exposure, 0)
        XCTAssertEqual(adj.highlights, 0)
        XCTAssertEqual(adj.shadows, 0)
        XCTAssertEqual(adj.vibrance, 0)
        XCTAssertEqual(adj.warmth, 0)
    }

    func testImageAdjustmentsIsIdentityFalseWhenNonZero() {
        var adj = SlideshowView.ImageAdjustments()
        adj.exposure = 0.5
        XCTAssertFalse(adj.isIdentity)
    }

    func testImageAdjustmentsRoundTripViaJSON() throws {
        var adj = SlideshowView.ImageAdjustments()
        adj.exposure = 1.0; adj.highlights = -0.5; adj.shadows = 0.3; adj.vibrance = 0.7; adj.warmth = -0.2
        var dict: [String: SlideshowView.ImageAdjustments] = [:]
        dict["file:///test/a.jpg"] = adj
        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([String: SlideshowView.ImageAdjustments].self, from: data)
        let result = decoded["file:///test/a.jpg"]!
        XCTAssertEqual(result.exposure, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.highlights, -0.5, accuracy: 0.001)
        XCTAssertEqual(result.shadows, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.vibrance, 0.7, accuracy: 0.001)
        XCTAssertEqual(result.warmth, -0.2, accuracy: 0.001)
    }

    func testAdjustmentCIFiltersAreValid() {
        XCTAssertNotNil(CIFilter(name: "CIExposureAdjust"))
        XCTAssertNotNil(CIFilter(name: "CIHighlightShadowAdjust"))
        XCTAssertNotNil(CIFilter(name: "CIVibrance"))
        XCTAssertNotNil(CIFilter(name: "CITemperatureAndTint"))
    }
}

// MARK: - Smart zoom notification tests

final class SmartZoomTests: XCTestCase {
    func testToggleSmartZoomNotificationFires() {
        let expectation = expectation(description: "toggleSmartZoom fires")
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleSmartZoom, object: nil, queue: .main
        ) { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .toggleSmartZoom, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testToggleSmartZoomNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.toggleSmartZoom.rawValue, "ToggleSmartZoom")
    }

    func testZoomPanControllerDefaultState() {
        let controller = ZoomPanController()
        XCTAssertEqual(controller.zoomScale, 1.0)
        XCTAssertEqual(controller.imageOffset, .zero)
    }

    func testZoomToSalientRegionNoopWithZeroWindowSize() {
        let controller = ZoomPanController()
        // windowSize defaults to .zero — zoomToSalientRegion should be a no-op
        let image = NSImage(size: CGSize(width: 100, height: 100))
        controller.zoomToSalientRegion(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), image: image, rotationAngle: .zero)
        // With zero windowSize the guard fires → no change
        XCTAssertEqual(controller.zoomScale, 1.0)
        XCTAssertEqual(controller.imageOffset, .zero)
    }
}

// MARK: - Face restoration notification tests

final class FaceRestoreNotificationTests: XCTestCase {
    func testRestoreFacesNotificationFires() {
        let exp = expectation(description: "restoreFaces fires")
        let obs = NotificationCenter.default.addObserver(forName: .restoreFaces, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .restoreFaces, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRemoveFaceRestorationNotificationFires() {
        let exp = expectation(description: "removeFaceRestoration fires")
        let obs = NotificationCenter.default.addObserver(forName: .removeFaceRestoration, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .removeFaceRestoration, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRestoreFacesNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.restoreFaces.rawValue, "RestoreFaces")
    }

    func testRemoveFaceRestorationNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.removeFaceRestoration.rawValue, "RemoveFaceRestoration")
    }

}

// MARK: - Red-eye removal notification tests

final class RedEyeRemovalNotificationTests: XCTestCase {
    func testRedEyeRemovalNotificationFires() {
        let exp = expectation(description: "redEyeRemoval fires")
        let obs = NotificationCenter.default.addObserver(forName: .redEyeRemoval, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .redEyeRemoval, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRemoveRedEyeNotificationFires() {
        let exp = expectation(description: "removeRedEye fires")
        let obs = NotificationCenter.default.addObserver(forName: .removeRedEye, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .removeRedEye, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRedEyeRemovalNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.redEyeRemoval.rawValue, "RedEyeRemoval")
    }

    func testRemoveRedEyeNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.removeRedEye.rawValue, "RemoveRedEye")
    }

    func testCIRedEyeCorrectionFilterIsAvailable() {
        XCTAssertNotNil(CIFilter(name: "CIRedEyeCorrection"), "CIRedEyeCorrection must be available on macOS 15")
    }
}

// MARK: - Background removal notification tests

final class BackgroundRemovalNotificationTests: XCTestCase {
    func testRemoveBackgroundNotificationFires() {
        let exp = expectation(description: "removeBackground fires")
        let obs = NotificationCenter.default.addObserver(forName: .removeBackground, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .removeBackground, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRestoreBackgroundNotificationFires() {
        let exp = expectation(description: "restoreBackground fires")
        let obs = NotificationCenter.default.addObserver(forName: .restoreBackground, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .restoreBackground, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRemoveBackgroundNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.removeBackground.rawValue, "RemoveBackground")
    }

    func testRestoreBackgroundNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.restoreBackground.rawValue, "RestoreBackground")
    }
}

// MARK: - Colorization notification tests

final class ColorizationNotificationTests: XCTestCase {
    func testColorizeImageNotificationFires() {
        let exp = expectation(description: "colorizeImage fires")
        let obs = NotificationCenter.default.addObserver(forName: .colorizeImage, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .colorizeImage, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testRemoveColorizationNotificationFires() {
        let exp = expectation(description: "removeColorization fires")
        let obs = NotificationCenter.default.addObserver(forName: .removeColorization, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .removeColorization, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testColorizeImageNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.colorizeImage.rawValue, "ColorizeImage")
    }

    func testRemoveColorizationNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.removeColorization.rawValue, "RemoveColorization")
    }
}

// MARK: - Fullscreen and zoom notification tests

final class FullScreenZoomNotificationTests: XCTestCase {
    func testToggleFullScreenNotificationFires() {
        let exp = expectation(description: "toggleFullScreen fires")
        let obs = NotificationCenter.default.addObserver(forName: .toggleFullScreen, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .toggleFullScreen, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testToggleFullScreenNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.toggleFullScreen.rawValue, "ToggleFullScreen")
    }

    func testZoomInNotificationFires() {
        let exp = expectation(description: "zoomIn fires")
        let obs = NotificationCenter.default.addObserver(forName: .zoomIn, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .zoomIn, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testZoomInNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.zoomIn.rawValue, "ZoomIn")
    }

    func testZoomOutNotificationFires() {
        let exp = expectation(description: "zoomOut fires")
        let obs = NotificationCenter.default.addObserver(forName: .zoomOut, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .zoomOut, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testZoomOutNotificationNameMatchesExpectedString() {
        XCTAssertEqual(NSNotification.Name.zoomOut.rawValue, "ZoomOut")
    }
}

// MARK: - Batch apply notification tests

final class BatchApplyNotificationTests: XCTestCase {
    func testBatchApplyAllNotificationFires() {
        let exp = expectation(description: "batchApplyAll fires")
        let obs = NotificationCenter.default.addObserver(forName: .batchApplyAll, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .batchApplyAll, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testBatchApplyFavouritesNotificationFires() {
        let exp = expectation(description: "batchApplyFavourites fires")
        let obs = NotificationCenter.default.addObserver(forName: .batchApplyFavourites, object: nil, queue: .main) { _ in exp.fulfill() }
        NotificationCenter.default.post(name: .batchApplyFavourites, object: nil)
        waitForExpectations(timeout: 1)
        NotificationCenter.default.removeObserver(obs)
    }

    func testBatchApplyNotificationNamesMatchExpectedStrings() {
        XCTAssertEqual(NSNotification.Name.batchApplyAll.rawValue, "BatchApplyAll")
        XCTAssertEqual(NSNotification.Name.batchApplyFavourites.rawValue, "BatchApplyFavourites")
    }

    func testBatchApplyNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [.batchApplyAll, .batchApplyFavourites]
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, names.count)
    }
}

// MARK: - Curves data model tests

final class CurvePointsTests: XCTestCase {
    func testDefaultIsIdentity() {
        let pts = CurvePoints()
        XCTAssertTrue(pts.isIdentity)
    }

    func testStaticIdentityMatchesDefault() {
        XCTAssertEqual(CurvePoints.identity, CurvePoints())
    }

    func testModifiedPointIsNotIdentity() {
        var pts = CurvePoints()
        pts.p2 = CGPoint(x: 0.5, y: 0.7)
        XCTAssertFalse(pts.isIdentity)
    }

    func testAsArrayReturnsAllFivePoints() {
        let pts = CurvePoints()
        XCTAssertEqual(pts.asArray.count, 5)
        XCTAssertEqual(pts.asArray[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(pts.asArray[4], CGPoint(x: 1, y: 1))
    }
}

final class CurvesDataTests: XCTestCase {
    func testDefaultIsIdentity() {
        let data = CurvesData()
        XCTAssertTrue(data.isIdentity)
    }

    func testModifiedAllChannelIsNotIdentity() {
        var data = CurvesData()
        data.all.p2 = CGPoint(x: 0.5, y: 0.8)
        XCTAssertFalse(data.isIdentity)
    }

    func testModifiedRedChannelIsNotIdentity() {
        var data = CurvesData()
        data.red.p1 = CGPoint(x: 0.25, y: 0.4)
        XCTAssertFalse(data.isIdentity)
    }

    func testModifiedGreenChannelIsNotIdentity() {
        var data = CurvesData()
        data.green.p3 = CGPoint(x: 0.75, y: 0.6)
        XCTAssertFalse(data.isIdentity)
    }

    func testModifiedBlueChannelIsNotIdentity() {
        var data = CurvesData()
        data.blue.p4 = CGPoint(x: 1, y: 0.9)
        XCTAssertFalse(data.isIdentity)
    }

    func testCurvesNotificationName() {
        XCTAssertEqual(NSNotification.Name.curvesImage.rawValue, "CurvesImage")
    }
}
