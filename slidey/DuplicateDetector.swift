import Foundation
import CoreGraphics

/// Perceptual-hash based duplicate / near-duplicate detection.
///
/// Uses a difference hash (dHash): the image is rendered to a small grayscale
/// grid and one bit is set per horizontally adjacent pixel pair depending on
/// which is brighter. dHash is tolerant of scaling, mild colour/brightness
/// shifts and re-compression, so two exports of the same shot (or burst-mode
/// near-dupes) hash to values a small Hamming distance apart.
///
/// Every function here is pure (CGImage / hash values in, values out) and has
/// no UI or filesystem dependency, so it is unit-testable in isolation.
enum DuplicateDetector {
    /// Side length of the hash grid. dHash compares horizontally adjacent
    /// pixels across a `hashSize` × `hashSize` grid, producing `hashSize²`
    /// bits, so we render one extra column (`hashSize + 1` wide).
    static let hashSize = 8

    /// Default Hamming-distance threshold at or below which two images are
    /// treated as near-duplicates. 0 means bit-identical hashes. 8 (out of 64
    /// bits) is a conservative starting point that catches re-encodes and
    /// light edits without merging visibly different photos; it is tunable.
    static let defaultThreshold = 8

    /// Computes a 64-bit difference hash from a CGImage. Returns nil if the
    /// image cannot be rendered into the grayscale scratch context.
    static func perceptualHash(_ cgImage: CGImage) -> UInt64? {
        let width = hashSize + 1
        let height = hashSize

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<height {
            for x in 0..<hashSize {
                let left = pixels[y * width + x]
                let right = pixels[y * width + x + 1]
                if left > right {
                    hash |= (UInt64(1) << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    /// Number of differing bits between two hashes (0 = identical).
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Groups URLs whose hashes are within `threshold` Hamming distance of one
    /// another and returns only groups with 2+ members.
    ///
    /// Grouping is transitive (union-find): if A~B and B~C, then A, B and C
    /// land in one group even if A and C are individually just over the
    /// threshold. This keeps a run of gradually-varying near-dupes together
    /// for review. Input order is preserved: groups appear in the order their
    /// first member appears, and members within a group keep input order.
    static func groupDuplicates(
        _ hashes: [(url: URL, hash: UInt64)],
        threshold: Int = defaultThreshold
    ) -> [[URL]] {
        let count = hashes.count
        guard count > 1 else { return [] }

        var parent = Array(0..<count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<count {
            for j in (i + 1)..<count where hammingDistance(hashes[i].hash, hashes[j].hash) <= threshold {
                union(i, j)
            }
        }

        var members: [Int: [URL]] = [:]
        var rootOrder: [Int] = []
        for i in 0..<count {
            let root = find(i)
            if members[root] == nil { rootOrder.append(root) }
            members[root, default: []].append(hashes[i].url)
        }

        return rootOrder.compactMap { root in
            guard let group = members[root], group.count >= 2 else { return nil }
            return group
        }
    }
}
