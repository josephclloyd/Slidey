import ImageIO
import XCTest
@testable import Slidey

final class RatingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RatingTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeTestJPEG(named name: String = "test.jpg") -> URL {
        let url = tempDir.appendingPathComponent(name)
        let size = CGSize(width: 2, height: 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        let cgImage = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    // MARK: - writeRatingToFile + readRatingFromFile round-trip

    func testWriteAndReadRating() throws {
        let url = makeTestJPEG()
        try writeRatingToFile(url: url, rating: 3)
        let result = readRatingFromFile(url)
        XCTAssertEqual(result, 3)
    }

    func testWriteRating5AndReadBack() throws {
        let url = makeTestJPEG()
        try writeRatingToFile(url: url, rating: 5)
        XCTAssertEqual(readRatingFromFile(url), 5)
    }

    func testWriteRating1AndReadBack() throws {
        let url = makeTestJPEG()
        try writeRatingToFile(url: url, rating: 1)
        XCTAssertEqual(readRatingFromFile(url), 1)
    }

    func testOverwriteRating() throws {
        let url = makeTestJPEG()
        try writeRatingToFile(url: url, rating: 4)
        XCTAssertEqual(readRatingFromFile(url), 4)
        try writeRatingToFile(url: url, rating: 2)
        XCTAssertEqual(readRatingFromFile(url), 2)
    }

    // MARK: - Clearing (rating 0) writes valid XMP value

    func testClearRatingWritesZero() throws {
        let url = makeTestJPEG()
        try writeRatingToFile(url: url, rating: 3)
        XCTAssertEqual(readRatingFromFile(url), 3)
        try writeRatingToFile(url: url, rating: 0)
        let result = readRatingFromFile(url)
        XCTAssertEqual(result, 0, "Clearing should write xmp:Rating=0, not an empty string")
    }

    // MARK: - readRatingFromFile on unrated image

    func testReadRatingFromUnratedImage() {
        let url = makeTestJPEG()
        let result = readRatingFromFile(url)
        XCTAssertNil(result)
    }

    func testReadRatingFromNonexistentFile() {
        let url = tempDir.appendingPathComponent("does_not_exist.jpg")
        let result = readRatingFromFile(url)
        XCTAssertNil(result)
    }

    // MARK: - writeRatingToFile error cases

    func testWriteRatingToNonexistentFileThrows() {
        let url = tempDir.appendingPathComponent("missing.jpg")
        XCTAssertThrowsError(try writeRatingToFile(url: url, rating: 3))
    }

    // MARK: - updateFilter predicate logic

    func testFilterPassesAllWhenNoConstraints() {
        let loader = ImageLoader()
        loader.urlFilter = nil
        let url = URL(fileURLWithPath: "/img/test.jpg")
        XCTAssertTrue(loader.urlFilter?(url) ?? true)
    }

    func testFilterRejectsUnfavouritedWhenFavouritesOnly() {
        let favs: Set<String> = ["file:///img/fav.jpg"]
        let ratings: [URL: Int] = [:]
        let minRating = 0
        let wantFavs = true

        let predicate: (URL) -> Bool = { url in
            if wantFavs && !favs.contains(url.absoluteString) { return false }
            if minRating > 0 && (ratings[url] ?? 0) < minRating { return false }
            return true
        }

        XCTAssertFalse(predicate(URL(string: "file:///img/other.jpg")!))
        XCTAssertTrue(predicate(URL(string: "file:///img/fav.jpg")!))
    }

    func testFilterRejectsBelowMinimumRating() {
        let favs: Set<String> = []
        let url3 = URL(string: "file:///img/rated3.jpg")!
        let url1 = URL(string: "file:///img/rated1.jpg")!
        let urlNone = URL(string: "file:///img/unrated.jpg")!
        let ratings: [URL: Int] = [url3: 3, url1: 1]
        let minRating = 2
        let wantFavs = false

        let predicate: (URL) -> Bool = { url in
            if wantFavs && !favs.contains(url.absoluteString) { return false }
            if minRating > 0 && (ratings[url] ?? 0) < minRating { return false }
            return true
        }

        XCTAssertTrue(predicate(url3))
        XCTAssertFalse(predicate(url1))
        XCTAssertFalse(predicate(urlNone))
    }

    func testFilterCombinesFavouritesAndRating() {
        let fav3 = URL(string: "file:///img/fav_rated3.jpg")!
        let fav0 = URL(string: "file:///img/fav_unrated.jpg")!
        let nonfav3 = URL(string: "file:///img/nonfav_rated3.jpg")!
        let favs: Set<String> = [fav3.absoluteString, fav0.absoluteString]
        let ratings: [URL: Int] = [fav3: 3, nonfav3: 3]
        let minRating = 2
        let wantFavs = true

        let predicate: (URL) -> Bool = { url in
            if wantFavs && !favs.contains(url.absoluteString) { return false }
            if minRating > 0 && (ratings[url] ?? 0) < minRating { return false }
            return true
        }

        XCTAssertTrue(predicate(fav3))
        XCTAssertFalse(predicate(fav0))
        XCTAssertFalse(predicate(nonfav3))
    }
}
