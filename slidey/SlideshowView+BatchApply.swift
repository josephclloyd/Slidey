import AppKit

extension SlideshowView {

    func batchApplyEdits(favouritesOnly: Bool) {
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
        let sourceCrop = cropRegions[sourceKey]
        let sourceLocalAdj = localAdjustmentURLLayers[sourceKey]

        let hasEdits = (sourceStack != nil && !sourceStack!.isEmpty)
            || (sourceAdj != nil && !sourceAdj!.isIdentity)
            || (sourceCurves != nil && !sourceCurves!.isIdentity)
            || (sourceVignette != nil && sourceVignette! > 0)
            || sourceRotation != nil
            || sourceFlipH || sourceFlipV
            || sourceEffect != nil
            || sourceCrop != nil
            || (sourceLocalAdj != nil && !sourceLocalAdj!.isEmpty)

        guard hasEdits else {
            savedToast = "No edits to apply"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No edits to apply" { self.savedToast = nil }
            }
            return
        }

        let batchableStack: EditStack? = sourceStack.flatMap { stack in
            var filtered = EditStack()
            for step in stack.steps {
                switch step {
                case .upscale, .faceRestore, .backgroundRemoval,
                     .artifactRemoval, .aiDenoise, .colorize, .redEyeRemoval:
                    continue
                default:
                    filtered.append(step)
                }
            }
            return filtered.isEmpty ? nil : filtered
        }

        var targetURLs: [URL]
        if favouritesOnly {
            targetURLs = imageLoader.allImageURLs.filter {
                $0 != sourceURL && favouriteURLStrings.contains($0.absoluteString)
            }
        } else {
            targetURLs = imageLoader.allImageURLs.filter { $0 != sourceURL }
        }

        guard !targetURLs.isEmpty else {
            let msg = favouritesOnly
                ? "No favourited images to apply edits to"
                : "No other images to apply edits to"
            savedToast = msg
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == msg { self.savedToast = nil }
            }
            return
        }

        let scopeLabel = favouritesOnly ? "favourited" : "all"
        let alert = NSAlert()
        alert.messageText = "Apply edits to \(targetURLs.count) \(scopeLabel) images?"
        var descriptions: [String] = []
        if let stack = batchableStack {
            descriptions.append(contentsOf: stack.steps.map { $0.titleTag })
        }
        if let adj = sourceAdj, !adj.isIdentity { descriptions.append("adjustments") }
        if let curves = sourceCurves, !curves.isIdentity { descriptions.append("curves") }
        if let v = sourceVignette, v > 0 { descriptions.append("vignette") }
        if sourceRotation != nil { descriptions.append("rotation") }
        if sourceFlipH || sourceFlipV { descriptions.append("flip") }
        if sourceEffect != nil { descriptions.append("photo effect") }
        if sourceCrop != nil { descriptions.append("crop") }
        if sourceLocalAdj != nil && !sourceLocalAdj!.isEmpty { descriptions.append("local adjustments") }
        alert.informativeText = "Edits: \(descriptions.joined(separator: ", "))"
            + "\n\nOriginal files are not modified. Edits apply in-session only."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for url in targetURLs {
            let key = url.absoluteString

            if let stack = batchableStack {
                editStacks[url] = stack
                for step in stack.steps {
                    clearCacheForStep(step.caseTag, url: url)
                }
            }
            effectImages[url] = nil

            if let adj = sourceAdj, !adj.isIdentity {
                adjustmentURLLevels[key] = adj
            } else {
                adjustmentURLLevels.removeValue(forKey: key)
            }

            if let curves = sourceCurves, !curves.isIdentity {
                curvesURLLevels[key] = curves
            } else {
                curvesURLLevels.removeValue(forKey: key)
            }

            if let v = sourceVignette, v > 0 {
                vignetteURLLevels[key] = v
            } else {
                vignetteURLLevels.removeValue(forKey: key)
            }

            if let d = sourceDenoise {
                denoiseURLLevels[key] = d
            } else {
                denoiseURLLevels.removeValue(forKey: key)
            }

            if let rotation = sourceRotation {
                rotationAngles[url] = rotation
            } else {
                rotationAngles.removeValue(forKey: url)
            }

            if sourceFlipH {
                flippedHorizontally.insert(key)
            } else {
                flippedHorizontally.remove(key)
            }
            if sourceFlipV {
                flippedVertically.insert(key)
            } else {
                flippedVertically.remove(key)
            }

            if let effect = sourceEffect {
                imageEffects[url] = effect
            } else {
                imageEffects.removeValue(forKey: url)
            }

            if let crop = sourceCrop {
                cropRegions[key] = crop
            } else {
                cropRegions.removeValue(forKey: key)
            }

            if let layers = sourceLocalAdj, !layers.isEmpty {
                localAdjustmentURLLayers[key] = layers
            } else {
                localAdjustmentURLLayers.removeValue(forKey: key)
            }
        }

        saveFavourites()
        updateDisplayImage()

        let message = "Applied edits to \(targetURLs.count) images"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }
}
