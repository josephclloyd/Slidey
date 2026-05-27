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
