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

final class RecentDirectoriesManagerTests: XCTestCase {
    private let testKey = "RecentDirectoriesTestKey_\(UUID().uuidString)"
    var recents: RecentDirectories!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        recents = RecentDirectories(userDefaultsKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testInsertEntryAddsToFront() {
        let a = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a")
        let b = RecentDirectory(bookmark: Data([2]), displayName: "B", path: "/b")

        recents.insertEntry(a)
        recents.insertEntry(b)

        XCTAssertEqual(recents.directories.count, 2)
        XCTAssertEqual(recents.directories[0].path, "/b")
        XCTAssertEqual(recents.directories[1].path, "/a")
    }

    func testDeduplication() {
        let a = RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a")
        let b = RecentDirectory(bookmark: Data([2]), displayName: "B", path: "/b")
        let aUpdated = RecentDirectory(bookmark: Data([3]), displayName: "A-Updated", path: "/a")

        recents.insertEntry(a)
        recents.insertEntry(b)
        recents.insertEntry(aUpdated)

        XCTAssertEqual(recents.directories.count, 2)
        XCTAssertEqual(recents.directories[0].path, "/a")
        XCTAssertEqual(recents.directories[0].displayName, "A-Updated")
        XCTAssertEqual(recents.directories[1].path, "/b")
    }

    func testMaxSizeTrimming() {
        let small = RecentDirectories(maxRecents: 3, userDefaultsKey: testKey)

        for i in 0..<5 {
            small.insertEntry(RecentDirectory(bookmark: Data([UInt8(i)]), displayName: "\(i)", path: "/path/\(i)"))
        }

        XCTAssertEqual(small.directories.count, 3)
        XCTAssertEqual(small.directories[0].path, "/path/4")
        XCTAssertEqual(small.directories[1].path, "/path/3")
        XCTAssertEqual(small.directories[2].path, "/path/2")
    }

    func testMaxSizeTrimmingDefaultCap() {
        for i in 0..<7 {
            recents.insertEntry(RecentDirectory(bookmark: Data([UInt8(i)]), displayName: "\(i)", path: "/path/\(i)"))
        }

        XCTAssertEqual(recents.directories.count, recents.maxRecents)
        XCTAssertEqual(recents.directories[0].path, "/path/6")
    }

    func testUserDefaultsRoundtrip() {
        let a = RecentDirectory(bookmark: Data([1, 2, 3]), displayName: "Photos", path: "/Users/test/Photos")
        let b = RecentDirectory(bookmark: Data([4, 5, 6]), displayName: "Desktop", path: "/Users/test/Desktop")

        recents.insertEntry(a)
        recents.insertEntry(b)

        let loaded = RecentDirectories(userDefaultsKey: testKey)

        XCTAssertEqual(loaded.directories.count, 2)
        XCTAssertEqual(loaded.directories[0].path, "/Users/test/Desktop")
        XCTAssertEqual(loaded.directories[0].bookmark, Data([4, 5, 6]))
        XCTAssertEqual(loaded.directories[1].path, "/Users/test/Photos")
        XCTAssertEqual(loaded.directories[1].bookmark, Data([1, 2, 3]))
    }

    func testEmptyOnFreshKey() {
        XCTAssertTrue(recents.directories.isEmpty)
    }

    func testInsertSamePathMovesToFront() {
        recents.insertEntry(RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a"))
        recents.insertEntry(RecentDirectory(bookmark: Data([2]), displayName: "B", path: "/b"))
        recents.insertEntry(RecentDirectory(bookmark: Data([3]), displayName: "C", path: "/c"))

        recents.insertEntry(RecentDirectory(bookmark: Data([1]), displayName: "A", path: "/a"))

        XCTAssertEqual(recents.directories.count, 3)
        XCTAssertEqual(recents.directories[0].path, "/a")
        XCTAssertEqual(recents.directories[1].path, "/c")
        XCTAssertEqual(recents.directories[2].path, "/b")
    }
}
