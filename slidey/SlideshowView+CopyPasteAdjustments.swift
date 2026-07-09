import AppKit

extension SlideshowView {

    func copyCurrentAdjustments() {
        guard let sourceURL = imageLoader.currentImageURL else { return }
        let sourceKey = sourceURL.absoluteString

        let sourceStack = editStacks[sourceURL]
        let sourceAdj = adjustmentURLLevels[sourceKey]
        let sourceCurves = curvesURLLevels[sourceKey]
        let sourceVignette = vignetteURLLevels[sourceKey]
        let sourceDenoise = denoiseURLLevels[sourceKey]
        let sourceRotation = rotationAngles[sourceURL]
        let sourceFlipH = flippedHorizontally.contains(sourceKey)
        let sourceFlipV = flippedVertically.contains(sourceKey)
        let sourceEffect = imageEffects[sourceURL]
        let sourceStraighten = straightenAngles[sourceKey]
        let sourcePerspective = perspectiveCorners[sourceKey]

        let batchableStack: EditStack? = sourceStack.flatMap { stack in
            var filtered = EditStack()
            for step in stack.steps {
                switch step {
                case .upscale, .faceRestore, .backgroundRemoval,
                     .artifactRemoval, .colorize, .redEyeRemoval:
                    continue
                default:
                    filtered.append(step)
                }
            }
            return filtered.isEmpty ? nil : filtered
        }

        let hasEdits = (batchableStack != nil)
            || (sourceAdj != nil && !sourceAdj!.isIdentity)
            || (sourceCurves != nil && !sourceCurves!.isIdentity)
            || (sourceVignette != nil && sourceVignette! > 0)
            || sourceDenoise != nil
            || sourceRotation != nil
            || sourceFlipH || sourceFlipV
            || sourceEffect != nil
            || sourceStraighten != nil
            || sourcePerspective != nil

        guard hasEdits else {
            savedToast = "No adjustments to copy"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No adjustments to copy" { self.savedToast = nil }
            }
            return
        }

        copiedAdjustments = CopiedAdjustments(
            editStack: batchableStack,
            adjustments: sourceAdj,
            curves: sourceCurves,
            vignetteIntensity: sourceVignette,
            denoiseLevel: sourceDenoise,
            rotationAngle: sourceRotation,
            flipH: sourceFlipH,
            flipV: sourceFlipV,
            effect: sourceEffect,
            straightenAngle: sourceStraighten,
            perspectiveCorners: sourcePerspective
        )

        let message = "Adjustments copied"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }

    func pasteAdjustments() {
        guard let copied = copiedAdjustments else {
            savedToast = "No adjustments copied"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No adjustments copied" { self.savedToast = nil }
            }
            return
        }

        guard let url = imageLoader.currentImageURL else { return }
        let key = url.absoluteString

        if let stack = copied.editStack {
            editStacks[url] = stack
            for step in stack.steps {
                clearCacheForStep(step.caseTag, url: url)
            }
        }
        effectImages[url] = nil

        if let adj = copied.adjustments, !adj.isIdentity {
            adjustmentURLLevels[key] = adj
        } else {
            adjustmentURLLevels.removeValue(forKey: key)
        }

        if let curves = copied.curves, !curves.isIdentity {
            curvesURLLevels[key] = curves
        } else {
            curvesURLLevels.removeValue(forKey: key)
        }

        if let v = copied.vignetteIntensity, v > 0 {
            vignetteURLLevels[key] = v
        } else {
            vignetteURLLevels.removeValue(forKey: key)
        }

        if let d = copied.denoiseLevel {
            denoiseURLLevels[key] = d
        } else {
            denoiseURLLevels.removeValue(forKey: key)
        }

        if let rotation = copied.rotationAngle {
            rotationAngles[url] = rotation
        } else {
            rotationAngles.removeValue(forKey: url)
        }

        if copied.flipH {
            flippedHorizontally.insert(key)
        } else {
            flippedHorizontally.remove(key)
        }
        if copied.flipV {
            flippedVertically.insert(key)
        } else {
            flippedVertically.remove(key)
        }

        if let effect = copied.effect {
            imageEffects[url] = effect
        } else {
            imageEffects.removeValue(forKey: url)
        }

        if let straighten = copied.straightenAngle {
            straightenAngles[key] = straighten
        } else {
            straightenAngles.removeValue(forKey: key)
        }

        if let perspective = copied.perspectiveCorners {
            perspectiveCorners[key] = perspective
        } else {
            perspectiveCorners.removeValue(forKey: key)
        }

        updateDisplayImage()

        let message = "Adjustments pasted"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }
}
