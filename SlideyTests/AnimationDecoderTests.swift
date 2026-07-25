import XCTest
import ImageIO
import UniformTypeIdentifiers
import AppKit
@testable import Slidey

final class AnimationDecoderTests: XCTestCase {

    /// Writes a multi-frame GIF with the given per-frame delays (seconds) to a
    /// temp file and returns its URL.
    private func makeGIF(delays: [Double]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anim-\(UUID().uuidString).gif")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, delays.count, nil
        ) else { throw XCTSkip("Could not create GIF destination") }

        for (i, delay) in delays.enumerated() {
            let img = NSImage(size: NSSize(width: 4, height: 4))
            img.lockFocus()
            (i % 2 == 0 ? NSColor.red : NSColor.blue).setFill()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
            img.unlockFocus()
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw XCTSkip("Could not rasterize frame")
            }
            let props: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ]
            CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func makeStaticPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("static-\(UUID().uuidString).png")
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not encode PNG")
        }
        try data.write(to: url)
        return url
    }

    func testMultiFrameGIFIsAnimated() throws {
        let url = try makeGIF(delays: [0.2, 0.2, 0.2])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(AnimationDecoder.isAnimated(url: url))
    }

    func testStaticPNGIsNotAnimated() throws {
        let url = try makeStaticPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(AnimationDecoder.isAnimated(url: url))
    }

    func testDecodeReturnsAllFramesAndDelays() throws {
        let url = try makeGIF(delays: [0.2, 0.3, 0.4])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = AnimationDecoder.decode(url: url)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.frames.count, 3)
        XCTAssertEqual(decoded?.delays.count, 3)
    }

    func testZeroDelayIsClampedToMinimum() throws {
        // GIFs with a 0s (or near-0s) delay must be clamped to 0.1s, matching
        // browser behaviour — a 0s delay is not "infinite speed".
        let url = try makeGIF(delays: [0.0, 0.0])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = AnimationDecoder.decode(url: url)
        XCTAssertNotNil(decoded)
        for delay in decoded?.delays ?? [] {
            XCTAssertGreaterThanOrEqual(delay, AnimationDecoder.minDelay)
        }
    }

    func testDecodeStaticPNGReturnsNil() throws {
        let url = try makeStaticPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(AnimationDecoder.decode(url: url))
    }
}
