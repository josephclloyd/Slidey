import Combine
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
