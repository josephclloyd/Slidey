import XCTest
import CoreGraphics
@testable import Slidey

final class DuplicateDetectorTests: XCTestCase {

    // MARK: - hammingDistance

    func testHammingDistanceIdentical() {
        XCTAssertEqual(DuplicateDetector.hammingDistance(0, 0), 0)
        XCTAssertEqual(DuplicateDetector.hammingDistance(.max, .max), 0)
        XCTAssertEqual(DuplicateDetector.hammingDistance(0xABCD, 0xABCD), 0)
    }

    func testHammingDistanceCountsDifferingBits() {
        XCTAssertEqual(DuplicateDetector.hammingDistance(0b0000, 0b1111), 4)
        XCTAssertEqual(DuplicateDetector.hammingDistance(0b1010, 0b0101), 4)
        XCTAssertEqual(DuplicateDetector.hammingDistance(0, .max), 64)
        XCTAssertEqual(DuplicateDetector.hammingDistance(0b0001, 0b0000), 1)
    }

    // MARK: - groupDuplicates

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).jpg")
    }

    func testGroupDuplicatesEmptyAndSingle() {
        XCTAssertTrue(DuplicateDetector.groupDuplicates([]).isEmpty)
        XCTAssertTrue(DuplicateDetector.groupDuplicates([(url("a"), 0x1)]).isEmpty)
    }

    func testGroupDuplicatesIdenticalHashesGroup() {
        let groups = DuplicateDetector.groupDuplicates([
            (url("a"), 0xFF),
            (url("b"), 0xFF),
            (url("c"), 0xFF),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0], [url("a"), url("b"), url("c")])
    }

    func testGroupDuplicatesDistinctHashesDoNotGroup() {
        // 0x0 and 0xFFFFFFFFFFFFFFFF differ in all 64 bits — far over threshold.
        let groups = DuplicateDetector.groupDuplicates([
            (url("a"), 0x0),
            (url("b"), UInt64.max),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupDuplicatesRespectsThresholdBoundary() {
        // Distance of exactly 8 bits.
        let base: UInt64 = 0
        let eightBitsSet: UInt64 = 0xFF
        XCTAssertEqual(DuplicateDetector.hammingDistance(base, eightBitsSet), 8)

        // threshold 8 → grouped (<=).
        XCTAssertEqual(
            DuplicateDetector.groupDuplicates([(url("a"), base), (url("b"), eightBitsSet)], threshold: 8).count,
            1
        )
        // threshold 7 → not grouped.
        XCTAssertTrue(
            DuplicateDetector.groupDuplicates([(url("a"), base), (url("b"), eightBitsSet)], threshold: 7).isEmpty
        )
    }

    func testGroupDuplicatesIsTransitive() {
        // A~B (dist 4) and B~C (dist 4) but A~C (dist 8) — all land in one
        // group at threshold 5 via transitivity even though A/C exceed it.
        let a: UInt64 = 0b0000_0000
        let b: UInt64 = 0b0000_1111
        let c: UInt64 = 0b1111_1111
        XCTAssertEqual(DuplicateDetector.hammingDistance(a, b), 4)
        XCTAssertEqual(DuplicateDetector.hammingDistance(b, c), 4)
        XCTAssertEqual(DuplicateDetector.hammingDistance(a, c), 8)

        let groups = DuplicateDetector.groupDuplicates(
            [(url("a"), a), (url("b"), b), (url("c"), c)],
            threshold: 5
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), Set([url("a"), url("b"), url("c")]))
    }

    func testGroupDuplicatesSeparatesUnrelatedGroups() {
        let groups = DuplicateDetector.groupDuplicates([
            (url("a1"), 0x00),
            (url("b1"), UInt64.max),
            (url("a2"), 0x00),
            (url("b2"), UInt64.max),
            (url("lonely"), 0x00FF00FF00FF00FF),
        ])
        XCTAssertEqual(groups.count, 2)
        // Order preserved: first group anchored by a1, second by b1.
        XCTAssertEqual(groups[0], [url("a1"), url("a2")])
        XCTAssertEqual(groups[1], [url("b1"), url("b2")])
    }

    // MARK: - perceptualHash

    private func makeSolidImage(gray: UInt8, size: Int = 64) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: CGFloat(gray) / 255.0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// Alternating vertical black/white stripes — produces many horizontal
    /// brightness transitions, so dHash yields a non-trivial (non-zero) value.
    /// A monotonic gradient or flat field would hash to all-zero because no
    /// horizontally adjacent pixel is brighter than the next.
    private func makeVerticalStripes(size: Int = 64, stripe: Int = 8) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        for x in 0..<size {
            let on = (x / stripe) % 2 == 0
            context.setFillColor(gray: on ? 1 : 0, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: size))
        }
        return context.makeImage()!
    }

    func testPerceptualHashIsDeterministicAndNonTrivial() {
        let image = makeVerticalStripes()
        let h1 = DuplicateDetector.perceptualHash(image)
        let h2 = DuplicateDetector.perceptualHash(image)
        XCTAssertNotNil(h1)
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, 0, "stripe pattern should produce a non-zero dHash")
    }

    func testPerceptualHashIdenticalContentMatches() {
        let a = makeVerticalStripes()
        let b = makeVerticalStripes()
        guard let ha = DuplicateDetector.perceptualHash(a),
              let hb = DuplicateDetector.perceptualHash(b) else {
            return XCTFail("hash returned nil")
        }
        XCTAssertEqual(DuplicateDetector.hammingDistance(ha, hb), 0)
    }

    func testPerceptualHashDistinguishesDifferentImages() {
        // A striped pattern and a flat field are visually unrelated and should
        // hash far apart (stripes set many bits, the solid field sets none).
        guard let stripes = DuplicateDetector.perceptualHash(makeVerticalStripes()),
              let solid = DuplicateDetector.perceptualHash(makeSolidImage(gray: 128)) else {
            return XCTFail("hash returned nil")
        }
        XCTAssertGreaterThan(
            DuplicateDetector.hammingDistance(stripes, solid),
            DuplicateDetector.defaultThreshold
        )
    }
}
