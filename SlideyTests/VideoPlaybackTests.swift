import AppKit
import AVFoundation
import XCTest
@testable import Slidey

final class VideoDetectionTests: XCTestCase {
    func testIsVideoAcceptsKnownContainers() {
        for ext in ["mov", "mp4", "m4v", "mkv"] {
            XCTAssertTrue(ImageLoader.isVideo(URL(fileURLWithPath: "/a/clip.\(ext)")),
                          "\(ext) should be treated as video")
        }
    }

    func testIsVideoIsCaseInsensitive() {
        XCTAssertTrue(ImageLoader.isVideo(URL(fileURLWithPath: "/a/clip.MOV")))
        XCTAssertTrue(ImageLoader.isVideo(URL(fileURLWithPath: "/a/clip.Mp4")))
    }

    func testIsVideoRejectsImagesAndOtherFiles() {
        for ext in ["jpg", "png", "gif", "heic", "avi", "txt"] {
            XCTAssertFalse(ImageLoader.isVideo(URL(fileURLWithPath: "/a/file.\(ext)")),
                           "\(ext) should not be treated as video")
        }
    }

    func testVideoExtensionsAreScanned() {
        let loader = ImageLoader()
        for ext in ImageLoader.videoExtensions {
            XCTAssertTrue(loader.supportedExtensions.contains(ext))
        }
    }
}

final class VideoDirectoryScanTests: XCTestCase {
    var loader: ImageLoader!
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        loader = ImageLoader()
        loader.sortOrder = .nameAscending
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoScanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent(name).path, contents: Data())
    }

    private func loadAndWait() {
        loader.loadImagesFromDirectory(url: tempDir)
        let exp = expectation(description: "Directory loaded")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 5)
    }

    func testScanIncludesVideoAlongsideImages() {
        touch("a.jpg")
        touch("b.mp4")
        touch("c.mov")
        loadAndWait()
        let names = Set(loader.imageURLs.map { $0.lastPathComponent })
        XCTAssertEqual(names, ["a.jpg", "b.mp4", "c.mov"])
    }

    func testScanStillExcludesUnsupportedVideo() {
        touch("a.jpg")
        touch("clip.avi")
        loadAndWait()
        let names = Set(loader.imageURLs.map { $0.lastPathComponent })
        XCTAssertEqual(names, ["a.jpg"])
    }
}

final class VideoThumbnailTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoThumbTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    func testThumbnailReturnsNilForInvalidVideoFile() {
        let url = tempDir.appendingPathComponent("broken.mp4")
        FileManager.default.createFile(atPath: url.path, contents: Data([0x00, 0x01, 0x02]))
        XCTAssertNil(ImageLoader.videoThumbnail(url: url, maxPixelSize: 128))
    }

    func testThumbnailExtractsFirstFrameFromRealVideo() throws {
        let size = CGSize(width: 96, height: 64)
        let url: URL
        do {
            url = try makeTestVideo(size: size)
        } catch {
            throw XCTSkip("Could not encode a test video in this environment: \(error)")
        }
        let thumb = try XCTUnwrap(ImageLoader.videoThumbnail(url: url, maxPixelSize: 256),
                                  "Expected a first-frame thumbnail")
        XCTAssertGreaterThan(thumb.size.width, 0)
        XCTAssertGreaterThan(thumb.size.height, 0)
        // The generator honours maximumSize, so the frame should not exceed it.
        XCTAssertLessThanOrEqual(thumb.size.width, 256)
        XCTAssertLessThanOrEqual(thumb.size.height, 256)
    }

    func testVideoFrameExtractsFullResolutionStill() throws {
        let size = CGSize(width: 96, height: 64)
        let url: URL
        do {
            url = try makeTestVideo(size: size)
        } catch {
            throw XCTSkip("Could not encode a test video in this environment: \(error)")
        }
        let frame = try XCTUnwrap(ImageLoader.videoFrame(url: url, at: .zero),
                                  "Expected a full-resolution still frame")
        // videoFrame does not downscale, so it should match the source dimensions.
        XCTAssertEqual(frame.size.width, size.width)
        XCTAssertEqual(frame.size.height, size.height)
    }

    // MARK: - Test video synthesis

    private enum VideoError: Error { case setup }

    private func makeTestVideo(size: CGSize) throws -> URL {
        let url = tempDir.appendingPathComponent("clip-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw VideoError.setup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoError.setup }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let buffer = makePixelBuffer(width: Int(size.width), height: Int(size.height)) else {
                throw VideoError.setup
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
        }
        input.markAsFinished()

        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        guard writer.status == .completed else { throw writer.error ?? VideoError.setup }
        return url
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
            ctx?.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1))
            ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }
}
