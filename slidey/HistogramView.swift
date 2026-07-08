import SwiftUI
import CoreImage
import AppKit

struct HistogramData {
    let red: [Float]
    let green: [Float]
    let blue: [Float]
    let luminance: [Float]

    private static let ciContext = CIContext()

    static func compute(from image: NSImage, bins: Int = 64) -> HistogramData? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIAreaHistogram") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: "inputExtent")
        filter.setValue(1.0, forKey: "inputScale")
        filter.setValue(bins, forKey: "inputCount")
        guard let output = filter.outputImage else { return nil }

        var pixelData = [Float](repeating: 0, count: bins * 4)
        pixelData.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            ciContext.render(output, toBitmap: base,
                            rowBytes: bins * 4 * MemoryLayout<Float>.stride,
                            bounds: output.extent, format: .RGBAf, colorSpace: nil)
        }

        var r = [Float](repeating: 0, count: bins)
        var g = [Float](repeating: 0, count: bins)
        var b = [Float](repeating: 0, count: bins)
        var l = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            r[i] = pixelData[i * 4]
            g[i] = pixelData[i * 4 + 1]
            b[i] = pixelData[i * 4 + 2]
            l[i] = 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i]
        }

        return HistogramData(red: r, green: g, blue: b, luminance: l)
    }
}

struct HistogramView: View {
    let data: HistogramData
    let showRGB: Bool

    var body: some View {
        Canvas { context, size in
            if showRGB {
                drawChannel(data.blue, color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5), in: context, size: size)
                drawChannel(data.green, color: Color.green.opacity(0.5), in: context, size: size)
                drawChannel(data.red, color: Color.red.opacity(0.5), in: context, size: size)
            } else {
                drawChannel(data.luminance, color: .white.opacity(0.6), in: context, size: size)
            }
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func drawChannel(_ values: [Float], color: Color,
                             in context: GraphicsContext, size: CGSize) {
        guard let maxVal = values.max(), maxVal > 0 else { return }

        let w = size.width
        let h = size.height
        let binWidth = w / CGFloat(values.count)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, value) in values.enumerated() {
            let x = CGFloat(i) * binWidth + binWidth / 2
            let barHeight = CGFloat(value / maxVal) * h
            path.addLine(to: CGPoint(x: x, y: h - barHeight))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        context.fill(path, with: .color(color))
    }
}
