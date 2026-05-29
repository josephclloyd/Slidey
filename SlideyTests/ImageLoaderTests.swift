import XCTest
@testable import Slidey

final class AppSortOrderTests: XCTestCase {
    func testAllCasesCount() {
        XCTAssertEqual(AppSortOrder.allCases.count, 7)
    }

    func testDisplayNames() {
        XCTAssertEqual(AppSortOrder.creationDateAscending.displayName, "Creation Date (Oldest First)")
        XCTAssertEqual(AppSortOrder.creationDateDescending.displayName, "Creation Date (Newest First)")
        XCTAssertEqual(AppSortOrder.modificationDateAscending.displayName, "Modification Date (Oldest First)")
        XCTAssertEqual(AppSortOrder.modificationDateDescending.displayName, "Modification Date (Newest First)")
        XCTAssertEqual(AppSortOrder.nameAscending.displayName, "Name (A → Z)")
        XCTAssertEqual(AppSortOrder.nameDescending.displayName, "Name (Z → A)")
        XCTAssertEqual(AppSortOrder.random.displayName, "Random")
    }

    func testRawValueRoundtrip() {
        for order in AppSortOrder.allCases {
            XCTAssertEqual(AppSortOrder(rawValue: order.rawValue), order)
        }
    }

    func testIdentifiable() {
        for order in AppSortOrder.allCases {
            XCTAssertEqual(order.id, order.rawValue)
        }
    }
}

final class SupportedExtensionTests: XCTestCase {
    var loader: ImageLoader!

    override func setUp() {
        super.setUp()
        loader = ImageLoader()
    }

    func testAcceptsJPEG() {
        XCTAssertTrue(loader.supportedExtensions.contains("jpg"))
        XCTAssertTrue(loader.supportedExtensions.contains("jpeg"))
    }

    func testAcceptsPNG() {
        XCTAssertTrue(loader.supportedExtensions.contains("png"))
    }

    func testAcceptsGIF() {
        XCTAssertTrue(loader.supportedExtensions.contains("gif"))
    }

    func testAcceptsBMP() {
        XCTAssertTrue(loader.supportedExtensions.contains("bmp"))
    }

    func testAcceptsTIFF() {
        XCTAssertTrue(loader.supportedExtensions.contains("tiff"))
    }

    func testAcceptsHEIC() {
        XCTAssertTrue(loader.supportedExtensions.contains("heic"))
    }

    func testAcceptsWebP() {
        XCTAssertTrue(loader.supportedExtensions.contains("webp"))
    }

    func testRejectsVideo() {
        XCTAssertFalse(loader.supportedExtensions.contains("mp4"))
        XCTAssertFalse(loader.supportedExtensions.contains("mov"))
        XCTAssertFalse(loader.supportedExtensions.contains("avi"))
    }

    func testRejectsText() {
        XCTAssertFalse(loader.supportedExtensions.contains("txt"))
        XCTAssertFalse(loader.supportedExtensions.contains("md"))
        XCTAssertFalse(loader.supportedExtensions.contains("json"))
    }

    func testRejectsPDF() {
        XCTAssertFalse(loader.supportedExtensions.contains("pdf"))
    }

    func testRejectsExecutable() {
        XCTAssertFalse(loader.supportedExtensions.contains("app"))
        XCTAssertFalse(loader.supportedExtensions.contains("dmg"))
    }
}

final class SortComparatorTests: XCTestCase {
    let now = Date()

    func makeEntries() -> [(url: URL, created: Date, modified: Date)] {
        [
            (url: URL(fileURLWithPath: "/img/banana.jpg"), created: now.addingTimeInterval(-200), modified: now.addingTimeInterval(-10)),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now.addingTimeInterval(-100), modified: now.addingTimeInterval(-30)),
            (url: URL(fileURLWithPath: "/img/cherry.jpg"), created: now.addingTimeInterval(-300), modified: now.addingTimeInterval(-20)),
        ]
    }

    func testCreationDateAscending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .creationDateAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["cherry.jpg", "banana.jpg", "apple.jpg"])
    }

    func testCreationDateDescending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .creationDateDescending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "banana.jpg", "cherry.jpg"])
    }

    func testModificationDateAscending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .modificationDateAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "cherry.jpg", "banana.jpg"])
    }

    func testModificationDateDescending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .modificationDateDescending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["banana.jpg", "cherry.jpg", "apple.jpg"])
    }

    func testNameAscending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "banana.jpg", "cherry.jpg"])
    }

    func testNameDescending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .nameDescending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["cherry.jpg", "banana.jpg", "apple.jpg"])
    }

    func testNameSortIsCaseInsensitive() {
        var entries: [(url: URL, created: Date, modified: Date)] = [
            (url: URL(fileURLWithPath: "/img/Banana.jpg"), created: now, modified: now),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now, modified: now),
            (url: URL(fileURLWithPath: "/img/Cherry.jpg"), created: now, modified: now),
        ]
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "Banana.jpg", "Cherry.jpg"])
    }

    func testRandomShufflesEntries() {
        var entries = (0..<50).map { i in
            (url: URL(fileURLWithPath: "/img/\(String(format: "%03d", i)).jpg"), created: now, modified: now)
        }
        let original = entries.map { $0.url }
        ImageLoader.sortEntries(&entries, by: .random)
        let shuffled = entries.map { $0.url }
        XCTAssertNotEqual(original, shuffled)
    }

    func testSortEmptyArray() {
        var entries: [(url: URL, created: Date, modified: Date)] = []
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSortSingleElement() {
        var entries: [(url: URL, created: Date, modified: Date)] = [
            (url: URL(fileURLWithPath: "/img/only.jpg"), created: now, modified: now)
        ]
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].url.lastPathComponent, "only.jpg")
    }
}

final class ImageLoaderNavigationTests: XCTestCase {
    var loader: ImageLoader!
    let dummyURLs = (0..<5).map { URL(fileURLWithPath: "/tmp/test\($0).jpg") }

    override func setUp() {
        super.setUp()
        loader = ImageLoader()
        loader.imageURLs = dummyURLs
        loader.currentIndex = 0
    }

    func testCurrentImageURL() {
        XCTAssertEqual(loader.currentImageURL, dummyURLs[0])
    }

    func testCurrentImageURLEmpty() {
        loader.imageURLs = []
        XCTAssertNil(loader.currentImageURL)
    }

    func testCurrentImageURLOutOfBounds() {
        loader.currentIndex = 10
        XCTAssertNil(loader.currentImageURL)
    }

    func testNextImageAdvancesIndex() {
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 1)
    }

    func testNextImageWrapsAround() {
        loader.currentIndex = 4
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testNextImageNoOpWhenEmpty() {
        loader.imageURLs = []
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testPreviousImageDecrementsIndex() {
        loader.currentIndex = 2
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 1)
    }

    func testPreviousImageWrapsAround() {
        loader.currentIndex = 0
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 4)
    }

    func testPreviousImageNoOpWhenEmpty() {
        loader.imageURLs = []
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testJumpToValidIndex() {
        loader.jumpTo(index: 3)
        XCTAssertEqual(loader.currentIndex, 3)
    }

    func testJumpToInvalidIndex() {
        loader.jumpTo(index: 10)
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testJumpToNegativeIndex() {
        loader.jumpTo(index: -1)
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testRemoveImageBeforeCurrent() {
        loader.currentIndex = 3
        loader.removeImage(at: dummyURLs[1])
        XCTAssertEqual(loader.currentIndex, 2)
        XCTAssertEqual(loader.imageURLs.count, 4)
    }

    func testRemoveImageAfterCurrent() {
        loader.currentIndex = 1
        loader.removeImage(at: dummyURLs[3])
        XCTAssertEqual(loader.currentIndex, 1)
        XCTAssertEqual(loader.imageURLs.count, 4)
    }

    func testRemoveCurrentImage() {
        loader.currentIndex = 2
        loader.removeImage(at: dummyURLs[2])
        XCTAssertEqual(loader.currentIndex, 2)
        XCTAssertEqual(loader.imageURLs.count, 4)
        XCTAssertEqual(loader.imageURLs[2], dummyURLs[3])
    }

    func testRemoveLastImageWhenCurrentIsLast() {
        loader.currentIndex = 4
        loader.removeImage(at: dummyURLs[4])
        XCTAssertEqual(loader.currentIndex, 3)
        XCTAssertEqual(loader.imageURLs.count, 4)
    }

    func testRemoveAllImages() {
        loader.imageURLs = [dummyURLs[0]]
        loader.currentIndex = 0
        loader.removeImage(at: dummyURLs[0])
        XCTAssertEqual(loader.imageURLs.count, 0)
        XCTAssertEqual(loader.currentIndex, 0)
        XCTAssertNil(loader.currentImage)
    }

    func testRemoveNonexistentImage() {
        let nonexistent = URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        loader.removeImage(at: nonexistent)
        XCTAssertEqual(loader.imageURLs.count, 5)
        XCTAssertEqual(loader.currentIndex, 0)
    }
}
