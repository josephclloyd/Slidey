import SwiftUI

extension EditStepTag {
    var undoActionName: String {
        switch self {
        case .enhance: return "Enhance"
        case .smooth: return "Smooth"
        case .sharpen: return "Sharpen"
        case .upscale: return "Upscale"
        case .faceRestore: return "Face Restore"
        case .redEyeRemoval: return "Red Eye Removal"
        case .backgroundRemoval: return "Background Removal"
        case .artifactRemoval: return "Artifact Removal"
        case .jpegCleanup: return "JPEG Cleanup"
        case .colorize: return "Colorize"
        case .grainReduction: return "Grain Reduction"
        case .objectRemoval: return "Object Removal"
        }
    }
}

extension SlideshowView {

    struct ImageEditSnapshot {
        let editStack: EditStack?
        let enhancedImage: NSImage?
        let smoothedImage: NSImage?
        let sharpenedImage: NSImage?
        let upscaledImage: NSImage?
        let upscaleFactor: Int?
        let faceRestoredImage: NSImage?
        let redEyedImage: NSImage?
        let backgroundRemovedImage: NSImage?
        let artifactRemovedImage: NSImage?
        let jpegCleanedImage: NSImage?
        let jpegCleanupRawImage: NSImage?
        let colorizedImage: NSImage?
        let grainReducedImage: NSImage?
        let grainReductionRawImage: NSImage?
        let objectRemovedImage: NSImage?
        let rotationAngle: Angle?
        let imageEffect: String?
        let effectImage: NSImage?

        let denoiseLevel: Double?
        let adjustments: ImageAdjustments?
        let curves: CurvesData?
        let vignetteIntensity: Double?
        let flipH: Bool
        let flipV: Bool
        let straightenAngle: Double?
        let perspectiveCornersValue: PerspectiveCorners?
        let localAdjustmentLayers: [LocalAdjustmentLayer]?
        let cropRegion: CropRegion?
    }

    func snapshotEditState(for url: URL) -> ImageEditSnapshot {
        let key = url.absoluteString
        return ImageEditSnapshot(
            editStack: editStacks[url],
            enhancedImage: enhancedImages[url],
            smoothedImage: smoothedImages[url],
            sharpenedImage: sharpenedImages[url],
            upscaledImage: upscaledImages[url],
            upscaleFactor: upscaleFactors[url],
            faceRestoredImage: faceRestoredImages[url],
            redEyedImage: redEyedImages[url],
            backgroundRemovedImage: backgroundRemovedImages[url],
            artifactRemovedImage: artifactRemovedImages[url],
            jpegCleanedImage: jpegCleanedImages[url],
            jpegCleanupRawImage: jpegCleanupRawImages[url],
            colorizedImage: colorizedImages[url],
            grainReducedImage: grainReducedImages[url],
            grainReductionRawImage: grainReductionRawImages[url],
            objectRemovedImage: objectRemovedImages[url],
            rotationAngle: rotationAngles[url],
            imageEffect: imageEffects[url],
            effectImage: effectImages[url],
            denoiseLevel: denoiseURLLevels[key],
            adjustments: adjustmentURLLevels[key],
            curves: curvesURLLevels[key],
            vignetteIntensity: vignetteURLLevels[key],
            flipH: flippedHorizontally.contains(key),
            flipV: flippedVertically.contains(key),
            straightenAngle: straightenAngles[key],
            perspectiveCornersValue: perspectiveCorners[key],
            localAdjustmentLayers: localAdjustmentURLLayers[key],
            cropRegion: cropRegions[key]
        )
    }

    func restoreEditState(_ snapshot: ImageEditSnapshot, for url: URL) {
        let key = url.absoluteString

        editStacks[url] = snapshot.editStack
        enhancedImages[url] = snapshot.enhancedImage
        smoothedImages[url] = snapshot.smoothedImage
        sharpenedImages[url] = snapshot.sharpenedImage
        upscaledImages[url] = snapshot.upscaledImage
        upscaleFactors[url] = snapshot.upscaleFactor
        faceRestoredImages[url] = snapshot.faceRestoredImage
        redEyedImages[url] = snapshot.redEyedImage
        backgroundRemovedImages[url] = snapshot.backgroundRemovedImage
        artifactRemovedImages[url] = snapshot.artifactRemovedImage
        jpegCleanedImages[url] = snapshot.jpegCleanedImage
        jpegCleanupRawImages[url] = snapshot.jpegCleanupRawImage
        colorizedImages[url] = snapshot.colorizedImage
        grainReducedImages[url] = snapshot.grainReducedImage
        grainReductionRawImages[url] = snapshot.grainReductionRawImage
        objectRemovedImages[url] = snapshot.objectRemovedImage
        rotationAngles[url] = snapshot.rotationAngle
        imageEffects[url] = snapshot.imageEffect
        effectImages[url] = snapshot.effectImage

        if let val = snapshot.denoiseLevel { denoiseURLLevels[key] = val } else { denoiseURLLevels.removeValue(forKey: key) }
        if let val = snapshot.adjustments { adjustmentURLLevels[key] = val } else { adjustmentURLLevels.removeValue(forKey: key) }
        if let val = snapshot.curves { curvesURLLevels[key] = val } else { curvesURLLevels.removeValue(forKey: key) }
        if let val = snapshot.vignetteIntensity { vignetteURLLevels[key] = val } else { vignetteURLLevels.removeValue(forKey: key) }
        if snapshot.flipH { flippedHorizontally.insert(key) } else { flippedHorizontally.remove(key) }
        if snapshot.flipV { flippedVertically.insert(key) } else { flippedVertically.remove(key) }
        if let val = snapshot.straightenAngle { straightenAngles[key] = val } else { straightenAngles.removeValue(forKey: key) }
        if let val = snapshot.perspectiveCornersValue { perspectiveCorners[key] = val } else { perspectiveCorners.removeValue(forKey: key) }
        if let val = snapshot.localAdjustmentLayers { localAdjustmentURLLayers[key] = val } else { localAdjustmentURLLayers.removeValue(forKey: key) }
        if let val = snapshot.cropRegion { cropRegions[key] = val } else { cropRegions.removeValue(forKey: key) }

        if imageLoader.currentImageURL == url {
            rotationAngle = snapshot.rotationAngle ?? .zero
        }
    }

    func registerUndoForEdit(url: URL, actionName: String) {
        guard !isRecomputingStep else { return }
        let snapshot = snapshotEditState(for: url)
        myWindow?.undoManager?.registerUndo(withTarget: imageLoader) { [self] _ in
            self.registerUndoForEdit(url: url, actionName: actionName)
            self.restoreEditState(snapshot, for: url)
            self.saveFavourites()
            self.updateDisplayImage()
        }
        myWindow?.undoManager?.setActionName(actionName)
    }
}
