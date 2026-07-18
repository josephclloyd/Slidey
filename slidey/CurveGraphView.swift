import SwiftUI

struct CurvePoints: Codable, Equatable {
    var p0: CGPoint = CGPoint(x: 0, y: 0)
    var p1: CGPoint = CGPoint(x: 0.25, y: 0.25)
    var p2: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var p3: CGPoint = CGPoint(x: 0.75, y: 0.75)
    var p4: CGPoint = CGPoint(x: 1, y: 1)
    var isIdentity: Bool {
        p0 == CGPoint(x: 0, y: 0) && p1 == CGPoint(x: 0.25, y: 0.25) &&
        p2 == CGPoint(x: 0.5, y: 0.5) && p3 == CGPoint(x: 0.75, y: 0.75) &&
        p4 == CGPoint(x: 1, y: 1)
    }
    var asArray: [CGPoint] { [p0, p1, p2, p3, p4] }
    static let identity = CurvePoints()
}

enum CurveChannel: String, CaseIterable {
    case all = "All"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
}

struct CurvesData: Codable, Equatable {
    var all: CurvePoints = .init()
    var red: CurvePoints = .init()
    var green: CurvePoints = .init()
    var blue: CurvePoints = .init()
    var isIdentity: Bool { all.isIdentity && red.isIdentity && green.isIdentity && blue.isIdentity }
}

struct CurveGraphView: View {
    @Binding var points: CurvePoints
    let channel: CurveChannel
    let onChanged: () -> Void

    private let graphSize: CGFloat = 280
    private let pointRadius: CGFloat = 8
    private let hitRadius: CGFloat = 20

    private var channelColor: Color {
        switch channel {
        case .all: return .white
        case .red: return .red
        case .green: return .green
        case .blue: return Color(red: 0.3, green: 0.5, blue: 1.0)
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let gridColor = Color.white.opacity(0.15)
            for i in 1..<4 {
                let frac = CGFloat(i) / 4
                var hLine = Path()
                hLine.move(to: CGPoint(x: 0, y: h * (1 - frac)))
                hLine.addLine(to: CGPoint(x: w, y: h * (1 - frac)))
                context.stroke(hLine, with: .color(gridColor), lineWidth: 0.5)
                var vLine = Path()
                vLine.move(to: CGPoint(x: w * frac, y: 0))
                vLine.addLine(to: CGPoint(x: w * frac, y: h))
                context.stroke(vLine, with: .color(gridColor), lineWidth: 0.5)
            }

            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: h))
            diagonal.addLine(to: CGPoint(x: w, y: 0))
            context.stroke(diagonal, with: .color(.white.opacity(0.25)), lineWidth: 1)

            let pts = points.asArray
            let curvePath = catmullRomPath(points: pts, size: size)
            context.stroke(curvePath, with: .color(channelColor), lineWidth: 2)

            for pt in pts {
                let center = CGPoint(x: pt.x * w, y: (1 - pt.y) * h)
                let rect = CGRect(
                    x: center.x - pointRadius,
                    y: center.y - pointRadius,
                    width: pointRadius * 2,
                    height: pointRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(channelColor))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
        }
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .gesture(curveDragGesture)
        .frame(width: graphSize, height: graphSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tone curve, \(channel.rawValue) channel")
        .accessibilityValue(accessibilityValueDescription)
        .accessibilityHint("Adjust to raise or lower the midtones")
        .accessibilityAdjustableAction { direction in
            let delta: CGFloat = direction == .increment ? 0.05 : -0.05
            let newY = min(max(points.p2.y + delta, 0), 1)
            points.p2 = CGPoint(x: points.p2.x, y: newY)
            onChanged()
        }
    }

    private var accessibilityValueDescription: String {
        if points.isIdentity {
            return "Linear, no change"
        }
        return "Midtone output \(Int((points.p2.y * 100).rounded())) percent"
    }

    private var curveDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let idx = nearestPointIndex(to: value.startLocation)
                updatePoint(at: idx, to: value.location)
            }
    }

    private func nearestPointIndex(to location: CGPoint) -> Int {
        let pts = points.asArray
        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, pt) in pts.enumerated() {
            let px = pt.x * graphSize
            let py = (1 - pt.y) * graphSize
            let dist = hypot(location.x - px, location.y - py)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    private func updatePoint(at index: Int, to location: CGPoint) {
        let x = min(max(location.x / graphSize, 0), 1)
        let y = min(max(1 - location.y / graphSize, 0), 1)

        let pts = points.asArray
        let minX: CGFloat
        let maxX: CGFloat
        switch index {
        case 0:
            minX = 0; maxX = 0
        case 4:
            minX = 1; maxX = 1
        default:
            minX = pts[index - 1].x + 0.01
            maxX = pts[index + 1].x - 0.01
        }

        let clampedX = min(max(x, minX), maxX)
        let newPoint = CGPoint(x: clampedX, y: y)

        switch index {
        case 0: points.p0 = newPoint
        case 1: points.p1 = newPoint
        case 2: points.p2 = newPoint
        case 3: points.p3 = newPoint
        case 4: points.p4 = newPoint
        default: break
        }
        onChanged()
    }

    private func catmullRomPath(points pts: [CGPoint], size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()

        let screenPts = pts.map { CGPoint(x: $0.x * w, y: (1 - $0.y) * h) }
        let count = screenPts.count
        guard count >= 2 else { return path }

        path.move(to: screenPts[0])

        let steps = 64
        for seg in 0..<(count - 1) {
            let p0 = screenPts[max(seg - 1, 0)]
            let p1 = screenPts[seg]
            let p2 = screenPts[min(seg + 1, count - 1)]
            let p3 = screenPts[min(seg + 2, count - 1)]

            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let t2 = t * t
                let t3 = t2 * t

                let x = 0.5 * ((2 * p1.x) +
                    (-p0.x + p2.x) * t +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                    (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) +
                    (-p0.y + p2.y) * t +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                    (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}
