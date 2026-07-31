import SwiftUI

struct CopiedAdjustments {
    var editStack: EditStack?
    var adjustments: SlideshowView.ImageAdjustments?
    var curves: CurvesData?
    var vignetteIntensity: Double?
    var selectiveColour: SelectiveColourSettings?
    var denoiseLevel: Double?
    var rotationAngle: Angle?
    var flipH: Bool
    var flipV: Bool
    var effect: String?
    var straightenAngle: Double?
    var perspectiveCorners: PerspectiveCorners?
    var localAdjustmentLayers: [LocalAdjustmentLayer]?
    var cropRegion: CropRegion?

    var hasEdits: Bool {
        (editStack != nil)
            || (adjustments != nil && !adjustments!.isIdentity)
            || (curves != nil && !curves!.isIdentity)
            || (vignetteIntensity != nil && vignetteIntensity! > 0)
            || selectiveColour != nil
            || denoiseLevel != nil
            || rotationAngle != nil
            || flipH || flipV
            || effect != nil
            || straightenAngle != nil
            || perspectiveCorners != nil
            || (localAdjustmentLayers != nil && !localAdjustmentLayers!.isEmpty)
            || cropRegion != nil
    }

    var descriptions: [String] {
        var result: [String] = []
        if let stack = editStack {
            result.append(contentsOf: stack.steps.map { $0.titleTag })
        }
        if let adj = adjustments, !adj.isIdentity { result.append("adjustments") }
        if let c = curves, !c.isIdentity { result.append("curves") }
        if let v = vignetteIntensity, v > 0 { result.append("vignette") }
        if selectiveColour != nil { result.append("selective colour") }
        if denoiseLevel != nil { result.append("denoise") }
        if rotationAngle != nil { result.append("rotation") }
        if flipH || flipV { result.append("flip") }
        if effect != nil { result.append("photo effect") }
        if straightenAngle != nil { result.append("straighten") }
        if perspectiveCorners != nil { result.append("perspective") }
        if let layers = localAdjustmentLayers, !layers.isEmpty { result.append("local adjustments") }
        if cropRegion != nil { result.append("crop") }
        return result
    }
}
