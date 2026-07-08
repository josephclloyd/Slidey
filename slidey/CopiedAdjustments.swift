import SwiftUI

struct CopiedAdjustments {
    var editStack: EditStack?
    var adjustments: SlideshowView.ImageAdjustments?
    var curves: CurvesData?
    var vignetteIntensity: Double?
    var denoiseLevel: Double?
    var rotationAngle: Angle?
    var flipH: Bool
    var flipV: Bool
    var effect: String?
    var straightenAngle: Double?
}
