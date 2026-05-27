import XCTest
@testable import Slidey

final class RecentDirectoryTests: XCTestCase {
    func testCodableRoundtrip() throws {
        let original = RecentDirectory(
            bookmark: Data([0x01, 0x02, 0x03]),
            displayName: "Photos",
            path: "/Users/test/Photos"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecentDirectory.self, from: encoded)

        XCTAssertEqual(decoded.bookmark, original.bookmark)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.path, original.path)
    }

    func testIdIsPath() {
        let entry = RecentDirectory(
            bookmark: Data(),
            displayName: "Test",
            path: "/some/path"
        )
        XCTAssertEqual(entry.id, "/some/path")
    }

    func testHashableEquality() {
        let a = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a")
        let b = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a")
        XCTAssertEqual(a, b)
    }

    func testHashableDifference() {
        let a = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a")
        let b = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/b")
        XCTAssertNotEqual(a, b)
    }

    func testCodableArrayRoundtrip() throws {
        let entries = [
            RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a"),
            RecentDirectory(bookmark: Data([2]), displayName: "B", path: "/b"),
        ]
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([RecentDirectory].self, from: encoded)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].path, "/a")
        XCTAssertEqual(decoded[1].path, "/b")
    }
}
