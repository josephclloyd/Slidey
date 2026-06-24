import Combine
import XCTest
@testable import Slidey

final class AppSortOrderTests: XCTestCase {
    func testAllCasesCount() {
        XCTAssertEqual(AppSortOrder.allCases.count, 9)
    }

    func testDisplayNames() {
        XCTAssertEqual(AppSortOrder.creationDateAscending.displayName, "Creation Date (Oldest First)")
        XCTAssertEqual(AppSortOrder.creationDateDescending.displayName, "Creation Date (Newest First)")
        XCTAssertEqual(AppSortOrder.modificationDateAscending.displayName, "Modification Date (Oldest First)")
        XCTAssertEqual(AppSortOrder.modificationDateDescending.displayName, "Modification Date (Newest First)")
        XCTAssertEqual(AppSortOrder.captureDateAscending.displayName, "Capture Date (Oldest First)")
        XCTAssertEqual(AppSortOrder.captureDateDescending.displayName, "Capture Date (Newest First)")
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

    func makeEntries() -> [(url: URL, created: Date, modified: Date, captured: Date?)] {
        [
            (url: URL(fileURLWithPath: "/img/banana.jpg"), created: now.addingTimeInterval(-200), modified: now.addingTimeInterval(-10), captured: now.addingTimeInterval(-150)),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now.addingTimeInterval(-100), modified: now.addingTimeInterval(-30), captured: now.addingTimeInterval(-50)),
            (url: URL(fileURLWithPath: "/img/cherry.jpg"), created: now.addingTimeInterval(-300), modified: now.addingTimeInterval(-20), captured: now.addingTimeInterval(-250)),
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

    func testCaptureDateAscending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .captureDateAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["cherry.jpg", "banana.jpg", "apple.jpg"])
    }

    func testCaptureDateDescending() {
        var entries = makeEntries()
        ImageLoader.sortEntries(&entries, by: .captureDateDescending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "banana.jpg", "cherry.jpg"])
    }

    func testCaptureDateAscendingNilsSortToEnd() {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = [
            (url: URL(fileURLWithPath: "/img/banana.jpg"), created: now, modified: now, captured: now.addingTimeInterval(-100)),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/cherry.jpg"), created: now, modified: now, captured: now.addingTimeInterval(-200)),
        ]
        ImageLoader.sortEntries(&entries, by: .captureDateAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["cherry.jpg", "banana.jpg", "apple.jpg"])
    }

    func testCaptureDateDescendingNilsSortToBeginning() {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = [
            (url: URL(fileURLWithPath: "/img/banana.jpg"), created: now, modified: now, captured: now.addingTimeInterval(-100)),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/cherry.jpg"), created: now, modified: now, captured: now.addingTimeInterval(-200)),
        ]
        ImageLoader.sortEntries(&entries, by: .captureDateDescending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "banana.jpg", "cherry.jpg"])
    }

    func testCaptureDateAllNilsFallBackToName() {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = [
            (url: URL(fileURLWithPath: "/img/cherry.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/banana.jpg"), created: now, modified: now, captured: nil),
        ]
        ImageLoader.sortEntries(&entries, by: .captureDateAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "banana.jpg", "cherry.jpg"])
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
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = [
            (url: URL(fileURLWithPath: "/img/Banana.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/apple.jpg"), created: now, modified: now, captured: nil),
            (url: URL(fileURLWithPath: "/img/Cherry.jpg"), created: now, modified: now, captured: nil),
        ]
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["apple.jpg", "Banana.jpg", "Cherry.jpg"])
    }

    func testRandomShufflesEntries() {
        var entries = (0..<50).map { i in
            (url: URL(fileURLWithPath: "/img/\(String(format: "%03d", i)).jpg"), created: now, modified: now, captured: nil as Date?)
        }
        let original = entries.map { $0.url }
        ImageLoader.sortEntries(&entries, by: .random)
        let shuffled = entries.map { $0.url }
        XCTAssertNotEqual(original, shuffled)
    }

    func testSortEmptyArray() {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = []
        ImageLoader.sortEntries(&entries, by: .nameAscending)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSortSingleElement() {
        var entries: [(url: URL, created: Date, modified: Date, captured: Date?)] = [
            (url: URL(fileURLWithPath: "/img/only.jpg"), created: now, modified: now, captured: nil)
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

    func testNextImageSingleElement() {
        loader.imageURLs = [dummyURLs[0]]
        loader.currentIndex = 0
        loader.nextImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }

    func testPreviousImageSingleElement() {
        loader.imageURLs = [dummyURLs[0]]
        loader.currentIndex = 0
        loader.previousImage()
        XCTAssertEqual(loader.currentIndex, 0)
    }
}

final class ImageLoaderFilterTests: XCTestCase {
    var loader: ImageLoader!
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        loader = ImageLoader()
        loader.sortOrder = .nameAscending

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLoaderFilterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for name in ["alpha.jpg", "bravo.jpg", "charlie.jpg", "delta.jpg", "echo.jpg"] {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent(name).path,
                contents: Data()
            )
        }
    }

    override func tearDown() {
        loader = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    private func loadAndWait() {
        loader.loadImagesFromDirectory(url: tempDir)
        let exp = expectation(description: "Directory loaded")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 5)
    }

    func testLoadPopulatesBothURLArrays() {
        loadAndWait()
        XCTAssertEqual(loader.imageURLs.count, 5)
        XCTAssertEqual(loader.allImageURLs.count, 5)
        XCTAssertEqual(loader.imageURLs, loader.allImageURLs)
    }

    func testFilterReducesVisibleURLs() {
        loadAndWait()
        let kept = Set(["alpha.jpg", "charlie.jpg", "echo.jpg"])
        loader.urlFilter = { kept.contains($0.lastPathComponent) }
        XCTAssertEqual(loader.imageURLs.count, 3)
        XCTAssertEqual(
            loader.imageURLs.map { $0.lastPathComponent },
            ["alpha.jpg", "charlie.jpg", "echo.jpg"]
        )
    }

    func testFilterPreservesAllImageURLs() {
        loadAndWait()
        loader.urlFilter = { $0.lastPathComponent == "alpha.jpg" }
        XCTAssertEqual(loader.allImageURLs.count, 5)
    }

    func testHasUnfilteredImagesAfterFilterToEmpty() {
        loadAndWait()
        loader.urlFilter = { _ in false }
        XCTAssertTrue(loader.hasUnfilteredImages)
    }

    func testHasUnfilteredImagesWhenNoLoad() {
        XCTAssertFalse(loader.hasUnfilteredImages)
    }

    func testRemoveFilterRestoresAllURLs() {
        loadAndWait()
        loader.urlFilter = { $0.lastPathComponent == "alpha.jpg" }
        XCTAssertEqual(loader.imageURLs.count, 1)
        loader.urlFilter = nil
        XCTAssertEqual(loader.imageURLs.count, 5)
    }

    func testFilterPreservesCurrentImagePosition() {
        loadAndWait()
        loader.jumpTo(index: 2)
        let currentName = loader.currentImageURL?.lastPathComponent
        XCTAssertEqual(currentName, "charlie.jpg")

        let kept = Set(["bravo.jpg", "charlie.jpg", "delta.jpg"])
        loader.urlFilter = { kept.contains($0.lastPathComponent) }
        XCTAssertEqual(loader.currentIndex, 1)
        XCTAssertEqual(loader.currentImageURL?.lastPathComponent, "charlie.jpg")
    }

    func testFilterAdjustsIndexWhenCurrentFilteredOut() {
        loadAndWait()
        loader.jumpTo(index: 4)
        XCTAssertEqual(loader.currentImageURL?.lastPathComponent, "echo.jpg")

        let kept = Set(["alpha.jpg", "bravo.jpg"])
        loader.urlFilter = { kept.contains($0.lastPathComponent) }
        XCTAssertEqual(loader.currentIndex, 1)
        XCTAssertTrue(loader.imageURLs.indices.contains(loader.currentIndex))
    }

    func testFilterToEmptySetsNilImage() {
        loadAndWait()
        loader.urlFilter = { _ in false }
        XCTAssertTrue(loader.imageURLs.isEmpty)
        XCTAssertEqual(loader.currentIndex, 0)
        XCTAssertNil(loader.currentImage)
    }

    func testRemoveImageDuringFilterUpdatesBothArrays() throws {
        loadAndWait()
        let kept = Set(["alpha.jpg", "charlie.jpg", "echo.jpg"])
        loader.urlFilter = { kept.contains($0.lastPathComponent) }

        let charlieURL = try XCTUnwrap(
            loader.allImageURLs.first { $0.lastPathComponent == "charlie.jpg" }
        )
        loader.removeImage(at: charlieURL)

        XCTAssertEqual(loader.imageURLs.count, 2)
        XCTAssertEqual(loader.allImageURLs.count, 4)
        XCTAssertFalse(loader.allImageURLs.contains(charlieURL))
    }

    func testRemoveFilteredOutImageFromAllURLs() throws {
        loadAndWait()
        loader.urlFilter = { $0.lastPathComponent != "bravo.jpg" }
        XCTAssertEqual(loader.imageURLs.count, 4)

        let bravoURL = try XCTUnwrap(
            loader.allImageURLs.first { $0.lastPathComponent == "bravo.jpg" }
        )
        loader.removeImage(at: bravoURL)

        XCTAssertEqual(loader.allImageURLs.count, 4)
        XCTAssertFalse(loader.allImageURLs.contains(bravoURL))
        XCTAssertEqual(loader.imageURLs.count, 4)
    }
}

final class ImageLoaderRenameTests: XCTestCase {
    var loader: ImageLoader!
    var tempDir: URL!
    var fileURLs: [URL]!
    let fileNames = ["alpha.jpg", "bravo.jpg", "charlie.jpg", "delta.jpg", "echo.jpg"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        loader = ImageLoader()
        loader.sortOrder = .nameAscending

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLoaderRenameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for name in fileNames {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        loader.loadImagesFromDirectory(url: tempDir)
        let exp = expectation(description: "Directory loaded")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 5)

        fileURLs = loader.imageURLs
    }

    override func tearDown() {
        loader = nil
        fileURLs = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testRenameUpdatesImageURLs() {
        let oldURL = fileURLs[2]
        let newURL = tempDir.appendingPathComponent("charlie_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)
        XCTAssertTrue(loader.imageURLs.contains(newURL))
        XCTAssertFalse(loader.imageURLs.contains(oldURL))
    }

    func testRenameUpdatesAllImageURLs() {
        let oldURL = fileURLs[2]
        let newURL = tempDir.appendingPathComponent("charlie_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)
        XCTAssertTrue(loader.allImageURLs.contains(newURL))
        XCTAssertFalse(loader.allImageURLs.contains(oldURL))
    }

    func testRenamePreservesIndex() {
        loader.jumpTo(index: 3)
        let oldURL = fileURLs[1]
        let newURL = tempDir.appendingPathComponent("bravo_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)
        XCTAssertEqual(loader.currentIndex, 3)
    }

    func testRenamePreservesIndexWhenRenamingCurrentImage() {
        loader.jumpTo(index: 2)
        let oldURL = fileURLs[2]
        let newURL = tempDir.appendingPathComponent("charlie_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)
        XCTAssertEqual(loader.currentIndex, 2)
        XCTAssertEqual(loader.imageURLs[2], newURL)
    }

    func testRenamePreservesArrayOrder() {
        let oldURL = fileURLs[2]
        let newURL = tempDir.appendingPathComponent("charlie_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)
        XCTAssertEqual(loader.imageURLs[0], fileURLs[0])
        XCTAssertEqual(loader.imageURLs[1], fileURLs[1])
        XCTAssertEqual(loader.imageURLs[2], newURL)
        XCTAssertEqual(loader.imageURLs[3], fileURLs[3])
        XCTAssertEqual(loader.imageURLs[4], fileURLs[4])
    }

    func testRenamePreservesImageCount() {
        let newURL = tempDir.appendingPathComponent("alpha_renamed.jpg")
        loader.renameImage(from: fileURLs[0], to: newURL)
        XCTAssertEqual(loader.imageURLs.count, 5)
        XCTAssertEqual(loader.allImageURLs.count, 5)
    }

    func testRenameNonexistentURLIsNoOp() {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        let newURL = tempDir.appendingPathComponent("whatever.jpg")
        let urlsBefore = loader.imageURLs
        let allBefore = loader.allImageURLs
        loader.renameImage(from: bogus, to: newURL)
        XCTAssertEqual(loader.imageURLs, urlsBefore)
        XCTAssertEqual(loader.allImageURLs, allBefore)
    }

    func testRenameFirstImage() {
        let newURL = tempDir.appendingPathComponent("alpha_renamed.jpg")
        loader.renameImage(from: fileURLs[0], to: newURL)
        XCTAssertEqual(loader.imageURLs[0], newURL)
        XCTAssertEqual(loader.allImageURLs[0], newURL)
    }

    func testRenameLastImage() {
        let newURL = tempDir.appendingPathComponent("echo_renamed.jpg")
        loader.renameImage(from: fileURLs[4], to: newURL)
        XCTAssertEqual(loader.imageURLs[4], newURL)
        XCTAssertEqual(loader.allImageURLs[4], newURL)
    }

    func testRenameWithFilterActive() {
        let kept = Set(["alpha.jpg", "charlie.jpg", "echo.jpg"])
        loader.urlFilter = { kept.contains($0.lastPathComponent) }
        XCTAssertEqual(loader.imageURLs.count, 3)

        let oldURL = loader.imageURLs[1]
        XCTAssertEqual(oldURL.lastPathComponent, "charlie.jpg")
        let newURL = tempDir.appendingPathComponent("charlie_renamed.jpg")
        loader.renameImage(from: oldURL, to: newURL)

        XCTAssertTrue(loader.imageURLs.contains(newURL))
        XCTAssertTrue(loader.allImageURLs.contains(newURL))
        XCTAssertFalse(loader.allImageURLs.contains(oldURL))
    }
}

final class DirectoryMissingTests: XCTestCase {
    var loader: ImageLoader!
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        loader = ImageLoader()
        loader.sortOrder = .nameAscending

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryMissingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for name in ["alpha.jpg", "bravo.jpg", "charlie.jpg"] {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent(name).path,
                contents: Data()
            )
        }
    }

    override func tearDown() {
        loader = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    private func loadAndWait() {
        loader.loadImagesFromDirectory(url: tempDir)
        let exp = expectation(description: "Directory loaded")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 5)
    }

    func testDirectoryMissingInitiallyFalse() {
        XCTAssertFalse(loader.directoryMissing)
    }

    func testDirectoryMissingAfterLoad() {
        loadAndWait()
        XCTAssertFalse(loader.directoryMissing)
    }

    func testDirectoryMissingDetectedOnDelete() throws {
        loadAndWait()
        XCTAssertFalse(loader.directoryMissing)

        try FileManager.default.removeItem(at: tempDir)

        let exp = expectation(description: "directoryMissing becomes true")
        let cancellable = loader.$directoryMissing
            .dropFirst()
            .filter { $0 }
            .sink { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        _ = cancellable

        XCTAssertTrue(loader.directoryMissing)
    }

    func testDirectoryMissingDetectedOnRename() throws {
        loadAndWait()
        XCTAssertFalse(loader.directoryMissing)

        let renamedDir = tempDir.deletingLastPathComponent()
            .appendingPathComponent("Renamed-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: tempDir, to: renamedDir)
        defer { try? FileManager.default.removeItem(at: renamedDir) }

        let exp = expectation(description: "directoryMissing becomes true")
        let cancellable = loader.$directoryMissing
            .dropFirst()
            .filter { $0 }
            .sink { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        _ = cancellable

        XCTAssertTrue(loader.directoryMissing)
    }

    func testDirectoryMissingClearedOnNewDirectory() throws {
        loadAndWait()

        try FileManager.default.removeItem(at: tempDir)

        let exp = expectation(description: "directoryMissing becomes true")
        let cancellable = loader.$directoryMissing
            .dropFirst()
            .filter { $0 }
            .sink { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        _ = cancellable

        XCTAssertTrue(loader.directoryMissing)

        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryMissingTests-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }
        for name in ["one.jpg", "two.jpg"] {
            FileManager.default.createFile(
                atPath: newDir.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        loader.loadImagesFromDirectory(url: newDir)
        let loadExp = expectation(description: "New directory loaded")
        DispatchQueue.main.async { loadExp.fulfill() }
        wait(for: [loadExp], timeout: 5)

        XCTAssertFalse(loader.directoryMissing)
    }

    func testDirectoryRecoveryAfterReappearing() throws {
        loadAndWait()

        try FileManager.default.removeItem(at: tempDir)

        let missingExp = expectation(description: "directoryMissing becomes true")
        let missingCancellable = loader.$directoryMissing
            .dropFirst()
            .filter { $0 }
            .sink { _ in missingExp.fulfill() }
        wait(for: [missingExp], timeout: 5)
        _ = missingCancellable

        XCTAssertTrue(loader.directoryMissing)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for name in ["alpha.jpg", "bravo.jpg"] {
            FileManager.default.createFile(
                atPath: tempDir.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        let recoveryExp = expectation(description: "directoryMissing becomes false")
        let recoveryCancellable = loader.$directoryMissing
            .dropFirst()
            .filter { !$0 }
            .sink { _ in recoveryExp.fulfill() }
        wait(for: [recoveryExp], timeout: 10)
        _ = recoveryCancellable

        XCTAssertFalse(loader.directoryMissing)
    }
}
