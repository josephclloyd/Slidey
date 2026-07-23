import SwiftUI

// Standalone RGB + luminosity histogram overlay (⌥H), separate from the
// histogram embedded in the Adjustments / Curves HUDs. Reflects the current
// post-edit display image and refreshes whenever that image changes.
extension SlideshowView {
    @ViewBuilder
    var histogramOverlay: some View {
        if showHistogramOverlay {
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Histogram")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        if let data = histogramOverlayData {
                            HistogramOverlayChart(data: data)
                                .frame(width: 220, height: 90)
                        } else {
                            Text("No image")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 220, height: 90)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("RGB histogram of the current image")
                }
                Spacer()
            }
        }
    }

    func toggleHistogramOverlay() {
        showHistogramOverlay.toggle()
        if showHistogramOverlay {
            refreshHistogramOverlay()
        } else {
            histogramOverlayData = nil
        }
    }

    func refreshHistogramOverlay() {
        guard showHistogramOverlay else { return }
        if let image = effectiveDisplayImage {
            histogramOverlayData = HistogramData.compute(from: image)
        } else {
            histogramOverlayData = nil
        }
    }
}

// Draws the three colour channels as translucent stacked fills with a
// luminosity outline on top, so exposure and per-channel clipping are visible
// at a glance.
private struct HistogramOverlayChart: View {
    let data: HistogramData

    var body: some View {
        Canvas { context, size in
            drawFill(data.blue, color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5), context: context, size: size)
            drawFill(data.green, color: Color.green.opacity(0.5), context: context, size: size)
            drawFill(data.red, color: Color.red.opacity(0.5), context: context, size: size)
            drawLine(data.luminance, color: .white.opacity(0.8), context: context, size: size)
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var overallMax: CGFloat {
        let m = max(data.red.max() ?? 0, data.green.max() ?? 0, data.blue.max() ?? 0, data.luminance.max() ?? 0)
        return CGFloat(m)
    }

    private func drawFill(_ values: [Float], color: Color, context: GraphicsContext, size: CGSize) {
        let maxVal = overallMax
        guard maxVal > 0, !values.isEmpty else { return }
        let binWidth = size.width / CGFloat(values.count)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, value) in values.enumerated() {
            let x = CGFloat(i) * binWidth + binWidth / 2
            let barHeight = CGFloat(value) / maxVal * size.height
            path.addLine(to: CGPoint(x: x, y: size.height - barHeight))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawLine(_ values: [Float], color: Color, context: GraphicsContext, size: CGSize) {
        let maxVal = overallMax
        guard maxVal > 0, !values.isEmpty else { return }
        let binWidth = size.width / CGFloat(values.count)
        var path = Path()
        for (i, value) in values.enumerated() {
            let x = CGFloat(i) * binWidth + binWidth / 2
            let barHeight = CGFloat(value) / maxVal * size.height
            let point = CGPoint(x: x, y: size.height - barHeight)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(color), lineWidth: 0.75)
    }
}
