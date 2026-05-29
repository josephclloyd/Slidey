import XCTest
@testable import Slidey

final class ParsePercentageTests: XCTestCase {
    func testSimplePercentage() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "50.00%"), 50.0)
    }

    func testIntegerPercentage() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "75%"), 75.0)
    }

    func testMultiplePercentagesReturnsLast() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "10.00% 25.00% 50.00%"), 50.0)
    }

    func testNoPercentageReturnsNil() {
        XCTAssertNil(SlideshowView.parseLastPercentage(in: "no percentage here"))
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(SlideshowView.parseLastPercentage(in: ""))
    }

    func testZeroPercent() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "0%"), 0.0)
    }

    func testHundredPercent() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "100%"), 100.0)
    }

    func testPercentageInLongerOutput() {
        let output = "[2024-01-01] Processing tile 3/4... 75.50%"
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: output), 75.5)
    }

    func testDecimalPrecision() {
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: "33.33%"), 33.33)
    }

    func testMultilineOutput() {
        let output = """
        Processing...
        10.00%
        20.00%
        30.00%
        """
        XCTAssertEqual(SlideshowView.parseLastPercentage(in: output), 30.0)
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
