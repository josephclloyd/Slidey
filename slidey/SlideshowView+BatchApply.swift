import AppKit

extension SlideshowView {

    func collectCopyableEdits(from url: URL) -> CopiedAdjustments {
        let key = url.absoluteString

        let batchableStack: EditStack? = editStacks[url].flatMap { stack in
            var filtered = EditStack()
            for step in stack.steps {
                switch step {
                case .upscale, .faceRestore, .backgroundRemoval,
                     .artifactRemoval, .jpegCleanup, .colorize, .redEyeRemoval, .grainReduction:
                    continue
                default:
                    filtered.append(step)
                }
            }
            return filtered.isEmpty ? nil : filtered
        }

        return CopiedAdjustments(
            editStack: batchableStack,
            adjustments: adjustmentURLLevels[key],
            curves: curvesURLLevels[key],
            vignetteIntensity: vignetteURLLevels[key],
            selectiveColour: selectiveColourURLLevels[key],
            denoiseLevel: denoiseURLLevels[key],
            rotationAngle: rotationAngles[url],
            flipH: flippedHorizontally.contains(key),
            flipV: flippedVertically.contains(key),
            effect: imageEffects[url],
            straightenAngle: straightenAngles[key],
            perspectiveCorners: perspectiveCorners[key],
            localAdjustmentLayers: localAdjustmentURLLayers[key],
            cropRegion: cropRegions[key]
        )
    }

    func applyCopiedEdits(_ copied: CopiedAdjustments, to url: URL) {
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

        if let selective = copied.selectiveColour {
            selectiveColourURLLevels[key] = selective
        } else {
            selectiveColourURLLevels.removeValue(forKey: key)
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

        if let layers = copied.localAdjustmentLayers, !layers.isEmpty {
            localAdjustmentURLLayers[key] = layers
        } else {
            localAdjustmentURLLayers.removeValue(forKey: key)
        }

        if let crop = copied.cropRegion {
            cropRegions[key] = crop
        } else {
            cropRegions.removeValue(forKey: key)
        }
    }

    func batchApplyEdits(favouritesOnly: Bool) {
        guard let sourceURL = imageLoader.currentImageURL else { return }

        let collected = collectCopyableEdits(from: sourceURL)

        guard collected.hasEdits else {
            savedToast = "No edits to apply"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No edits to apply" { self.savedToast = nil }
            }
            return
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
        alert.informativeText = "Edits: \(collected.descriptions.joined(separator: ", "))"
            + "\n\nOriginal files are not modified. Edits apply in-session only."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for url in targetURLs {
            applyCopiedEdits(collected, to: url)
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
